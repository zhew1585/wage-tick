#!/usr/bin/env python3
"""真窗口截图与交互回归：用临时目录里的假数据拉起 Debug 版 App，经注入的 harness/drive.m 在 App 进程里合成按键、点击，读窗口状态。

由 ui-checks-mac.sh 调用，不单独用：
  python3 scripts/checks/ui_drive.py --exe <App 可执行文件> --dylib <libdrive.dylib> --home <假主目录> --out <输出目录>
做两件事：
  1. 截真窗口图 today、P3-goals、P4-history、P5-calendar、P5-day-detail、P6-settings (2 倍，整窗含红绿灯)，写 realwindow/manifest.json。
  2. 交互回归 ACT-PUSH、ACT-HOME、ACT-ESC、ACT-SHEET、ACT-GOALCARD、ACT-DOCK、ACT-COVER、ACT-HISTORY (规则见 README)。
认页靠像素：页头区域 (窗口顶部 4–44pt、红绿灯右边) 的墨迹指纹与本次运行里 ⌘2、⌘3、⌘, 截下的参照逐像素相同；
概览靠底部入口栏 (历史、目标、设置那一条) 的指纹与启动时的参照相同。两块都避开了时钟与滚动的数字。
退出码：0 全部通过；1 有规则不过；2 blocked (窗口没出现、驱动连不上等环境问题)。
"""
import argparse, datetime, json, os, re, signal, socket, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ui_geometry  # noqa: E402

GEOMETRY = json.load(open(os.path.join(HERE, 'ui-geometry.json'), encoding='utf-8'))
# 页头区域：红绿灯右边到窗口右沿，顶部 4–44pt (概览的日期时钟从 46 起，不在里面)。
HEADER = (76, 4, 284, 40)
# 墨迹阈值：深色的字与图标；悬停时浅色的圆角底不算。
INK = 160
FOOTER_HEIGHT = 46


class Blocked(Exception):
    """环境问题，没法判断。"""


class Driver:
    """和注入库说话：一行命令，一行 JSON 回复。"""

    def __init__(self, workdir, name, timeout):
        self.workdir, self.name, self.timeout = workdir, name, timeout
        self.file = None

    def connect(self, deadline):
        # 套接字路径相对工作目录，避开 Unix 套接字 104 字节的路径上限。
        while time.time() < deadline:
            try:
                sock = socket.socket(socket.AF_UNIX)
                sock.settimeout(self.timeout)
                cwd = os.getcwd()
                os.chdir(self.workdir)
                try:
                    sock.connect(self.name)
                finally:
                    os.chdir(cwd)
                self.file = sock.makefile('rw', encoding='utf-8')
                return
            except OSError:
                time.sleep(0.2)
        raise Blocked('连不上注入的驱动 (App 没起来，或 DYLD_INSERT_LIBRARIES 没生效)')

    def send(self, line):
        try:
            self.file.write(line + '\n')
            self.file.flush()
            reply = self.file.readline()
        except (OSError, socket.timeout) as error:
            raise Blocked(f'驱动没有回应 ({line}): {error}')
        if not reply:
            raise Blocked(f'驱动断开了 ({line})：App 可能已经崩溃')
        data = json.loads(reply)
        if 'error' in data:
            raise Blocked(f'驱动报错 ({line}): {data["error"]}')
        return data


class Run:
    def __init__(self, args):
        self.args = args
        self.out = args.out
        self.drive = None
        self.app = None
        self.failures, self.passes, self.notes = [], [], []
        self.refs = {}
        self.window_number = None
        self.fail_count = 0

    # MARK: 基本动作

    def state(self):
        return self.drive.send('state')

    def key(self, name):
        self.drive.send(f'key {name}')

    def click(self, x, y):
        self.drive.send(f'click {x:.1f} {y:.1f}')

    def snap(self, path):
        self.drive.send(f'snap {path}')

    def sig(self, rect):
        x, y, w, h = rect
        return self.drive.send(f'sig {x} {y} {w} {h} {INK}')['hash']

    def footer_rect(self):
        height = self.state().get('height', 760)
        return (0, height - FOOTER_HEIGHT, 360, FOOTER_HEIGHT)

    def ax(self):
        return self.drive.send('ax')['elements']

    def find(self, role, pattern, below=None):
        """按辅助功能里的文字找元素 (正则匹配 label 或 value)，返回中心点 (pt)。"""
        for element in self.ax():
            text = element['label'] or element['value']
            if element['role'] == role and re.search(pattern, text) and (below is None or element['y'] >= below):
                return element['x'] + element['w'] / 2, element['y'] + element['h'] / 2, text
        return None

    def ax_title(self):
        """页头里的按钮 (返回加标题) 的文字，如「目标」；概览上没有。"""
        for element in self.ax():
            if element['role'] == 'AXButton' and element['y'] < 44 and element['x'] > 76 and element['label'] not in ('钉住', ''):
                return element['label']
        return None

    def settle(self, minimum=0.45, timeout=4.0):
        """等动画停下：页头与底部入口栏的指纹连续两次相同。返回 (页头, 底栏)。"""
        time.sleep(minimum)
        deadline = time.time() + timeout
        previous = None
        while True:
            current = (self.sig(HEADER), self.sig(self.footer_rect()))
            if current == previous or time.time() > deadline:
                return current
            previous = current
            time.sleep(0.15)

    def where(self):
        """现在是哪一页：goals、history、settings、calendar、day、overview，认不出时 unknown。"""
        header, footer = self.settle()
        for name in ('goals', 'history', 'settings', 'calendar', 'day'):
            if self.refs.get(name) == header:
                return name
        if footer == self.refs.get('footer'):
            return 'overview'
        return 'unknown'

    def sheet(self, expected, timeout=2.0):
        """等 attachedSheet 变成 expected (sheet 弹出、收起有动画)；返回最后读到的值。"""
        deadline = time.time() + timeout
        while True:
            value = bool(self.state().get('sheet'))
            if value == expected or time.time() > deadline:
                return value
            time.sleep(0.1)

    def visible(self, expected, timeout=2.0):
        deadline = time.time() + timeout
        while True:
            value = bool(self.state().get('visible'))
            if value == expected or time.time() > deadline:
                return value
            time.sleep(0.1)

    # MARK: 结果

    def fail(self, rule, text):
        self.fail_count += 1
        evidence = os.path.join(self.out, f'fail-{rule}-{self.fail_count}.png')
        try:
            self.snap(evidence)
            text += f' (当时的窗口图：{evidence})'
        except Blocked:
            pass
        self.failures.append(f'FAIL [{rule}] {text}')
        print(self.failures[-1], flush=True)
        return False

    def ok(self, rule, text):
        self.passes.append(f'ok [{rule}] {text}')
        print(self.passes[-1], flush=True)
        return True

    def expect(self, rule, page, doing):
        """断言现在在 page 上，不是就记一条 FAIL。"""
        now = self.where()
        if now != page:
            return self.fail(rule, f'{doing}之后应在{NAMES[page]}，实际是{NAMES.get(now, now)}')
        return True

    def home(self):
        """回到概览作为每条规则的起点 (⌘1；窗口关着时 ⌘1 也会打开它)。"""
        self.key('cmd-1')
        if not self.visible(True):
            raise Blocked('⌘1 之后今日概览窗口没出现')
        return self.where() == 'overview'

    # MARK: 启动

    def launch(self):
        env = dict(os.environ)
        env.update({
            'CFFIXED_USER_HOME': self.args.home,
            'WAGETICK_FAKE_HOME': self.args.home,
            'WAGETICK_DRIVE_SOCKET': 'drive.sock',
            'DYLD_INSERT_LIBRARIES': self.args.dylib,
        })
        env.pop('WAGETICK_RENDER_DIR', None)
        log = open(os.path.join(self.out, 'app.log'), 'w')
        self.app = subprocess.Popen([self.args.exe], cwd=self.args.workdir, env=env, stdout=log, stderr=subprocess.STDOUT)
        with open(os.path.join(self.args.workdir, 'app.pid'), 'w') as pid:
            pid.write(str(self.app.pid))
        self.drive = Driver(self.args.workdir, 'drive.sock', 15)
        deadline = time.time() + self.args.launch_timeout
        self.drive.connect(deadline)
        while time.time() < deadline:
            state = self.state()
            if state.get('exists') and state.get('visible'):
                self.window_number = state['number']
                self.screen_scale = 1 if state.get('scale', 2) < 1.5 else 2
                return state
            if self.app.poll() is not None:
                raise Blocked(f'App 启动后退出了 (退出码 {self.app.returncode})，见 {self.out}/app.log')
            time.sleep(0.3)
        raise Blocked(f'{self.args.launch_timeout} 秒内今日概览窗口没出现 (没有图形会话，或启动卡住了)；窗口状态：{self.state()}')

    def stop(self):
        if self.app and self.app.poll() is None:
            try:
                self.drive.send('quit')
                self.app.wait(timeout=10)
            except (Blocked, subprocess.TimeoutExpired, AttributeError):
                pass
        if self.app and self.app.poll() is None:
            self.app.kill()
            self.app.wait()

    # MARK: 真窗口图

    def capture(self, name):
        self.settle()
        path = os.path.join(self.out, 'realwindow', name + '.png')
        self.snap(path)
        return name + '.png'

    def write_manifest(self, files, active):
        commit = subprocess.run(['git', 'rev-parse', 'HEAD'], capture_output=True, text=True, cwd=HERE).stdout.strip()
        manifest = {
            'commit': commit,
            'kind': 'realwindow',
            'capturedAt': datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
            'method': 'cacheDisplay：注入 Debug 版 App，对窗框视图 (NSThemeFrame，含系统红绿灯) 调 cacheDisplay(in:to:)，存成 2 倍图 (1 倍屏上是放大的，见 screenScale)；假数据在临时目录',
            'decorations': {'windowFrame': True, 'trafficLights': True, 'active': active},
            'screenScale': self.screen_scale,
            'files': files,
        }
        with open(os.path.join(self.out, 'realwindow', 'manifest.json'), 'w', encoding='utf-8') as out:
            json.dump(manifest, out, ensure_ascii=False, indent=2)

    # MARK: 规则

    def act_push(self, files):
        """⌘2、⌘3、⌘, 在同一个窗口里推进来对应的页面；顺带截下三页的参照与真窗口图。"""
        good = True
        for key, page, title, image in (('cmd-2', 'goals', '目标', 'P3-goals'), ('cmd-3', 'history', '历史', 'P4-history'), ('cmd-comma', 'settings', '设置', 'P6-settings')):
            self.key(key)
            header, footer = self.settle()
            state = self.state()
            label = KEYS[key]
            if state.get('number') != self.window_number or state.get('visibleTitled') != ['今日概览']:
                good = self.fail('ACT-PUSH', f'{label} 之后不是原来那一个窗口：{state}')
            if footer == self.refs['footer'] or header in self.refs.values():
                good = self.fail('ACT-PUSH', f'{label} 之后画面没换成{title}页 (页头或底栏和之前的某一页一样)')
            if self.ax_title() != title:
                good = self.fail('ACT-PUSH', f'{label} 之后页头的标题是 {self.ax_title()!r}，应是 {title!r}')
            measured = self.header_geometry()
            if not measured or not measured.get('arrow'):
                good = self.fail('ACT-PUSH', f'{label} 之后页头里没找到返回箭头')
            self.refs[page] = header
            files.append(self.capture(image))
        if good:
            self.ok('ACT-PUSH', '⌘2、⌘3、⌘, 在同一个窗口里推进来目标、历史、设置，三页页头各不相同')
        return good

    def header_geometry(self):
        path = os.path.join(self.args.workdir, 'header.png')
        self.snap(path)
        width, height, rows, pixel = ui_geometry.load_png(path, max_rows=140 * 2)
        return ui_geometry.measure_header(pixel, width, rows, 0, 0, GEOMETRY)

    def act_dock(self):
        if not self.home():
            return self.fail('ACT-DOCK', '⌘1 回不到概览，没法开始')
        self.key('cmd-comma')
        if not self.expect('ACT-DOCK', 'settings', '⌘,'):
            return False
        self.drive.send('reopen')
        if self.expect('ACT-DOCK', 'settings', '点 Dock 图标 (applicationShouldHandleReopen)'):
            return self.ok('ACT-DOCK', '停在设置页时点 Dock 图标，仍在设置页')
        return False

    def act_home(self):
        if not self.home():
            return self.fail('ACT-HOME', '⌘1 回不到概览，没法开始')
        self.key('cmd-2')
        if not self.expect('ACT-HOME', 'goals', '⌘2'):
            return False
        self.key('cmd-1')
        if self.expect('ACT-HOME', 'overview', '停在目标页按 ⌘1'):
            return self.ok('ACT-HOME', '停在目标页按 ⌘1，回到概览')
        return False

    def act_goalcard(self):
        if not self.home():
            return self.fail('ACT-GOALCARD', '⌘1 回不到概览，没法开始')
        # 按卡片上的目标名找位置 (卡片是按钮时整张卡是一个元素，不是按钮时是名字那一行字)，点下去看进没进目标页。
        card = self.find('AXButton', '^换台 MacBook') or self.find('AXStaticText', '^换台 MacBook$')
        if not card:
            return self.fail('ACT-GOALCARD', '概览上找不到累计中目标「换台 MacBook」的卡片')
        self.click(card[0], card[1])
        if self.expect('ACT-GOALCARD', 'goals', f'点概览上的目标卡 ({card[0]:.0f}, {card[1]:.0f})'):
            return self.ok('ACT-GOALCARD', '点概览上累计中目标的卡片，进入目标页')
        return False

    def act_cover(self, deduction):
        if not self.home():
            return self.fail('ACT-COVER', '⌘1 回不到概览，没法开始')
        self.key('cmd-2')
        if not self.expect('ACT-COVER', 'goals', '⌘2'):
            return False
        x, y = deduction
        self.click(x, y)
        good = self.expect('ACT-COVER', 'goals', f'目标页盖着时在概览「今天扣钱了」的位置 ({x:.0f}, {y:.0f}) 点一下')
        if self.state().get('sheet'):
            good = self.fail('ACT-COVER', '点了之后弹出了表单')
        self.key('cmd-1')
        if good and self.where() != 'overview':
            good = self.fail('ACT-COVER', '回到概览后不是概览 (底栏不见了，多半是扣钱表单被底下的按钮打开了)')
        if good:
            return self.ok('ACT-COVER', '目标页盖着时点底下「今天扣钱了」的位置，页面不变，回到概览也没有扣钱表单')
        return False

    def act_sheet(self):
        if not self.home():
            return self.fail('ACT-SHEET', '⌘1 回不到概览，没法开始')
        self.key('cmd-2')
        if not self.expect('ACT-SHEET', 'goals', '⌘2'):
            return False
        button = self.find('AXButton', '^新目标$')
        if not button:
            return self.fail('ACT-SHEET', '目标页上找不到「新目标」按钮')
        self.click(button[0], button[1])
        if not self.sheet(True):
            return self.fail('ACT-SHEET', '点「新目标」后没有弹出表单 (attachedSheet 为空)')
        # 挂着 sheet 时窗口整体压暗，页头指纹和平时不同：先截一份「开着表单的目标页」作参照，之后每按一次都要与它逐像素相同。
        covered, _ = self.settle()
        if self.ax_title() != '目标':
            return self.fail('ACT-SHEET', f'弹出表单时页头不是目标页 ({self.ax_title()!r})')
        good = True
        for key in ('cmd-1', 'cmd-2', 'cmd-3', 'cmd-comma'):
            self.key(key)
            header, _ = self.settle()
            if not self.state().get('sheet'):
                good = self.fail('ACT-SHEET', f'开着「新目标」表单时按 {KEYS[key]}，表单没了')
                break
            if header != covered:
                good = self.fail('ACT-SHEET', f'开着「新目标」表单时按 {KEYS[key]}，底下的页面变了 (页头和按键前不同，标题现在是 {self.ax_title()!r})')
                break
        if self.state().get('sheet'):
            self.key('esc')
            if self.sheet(False):
                good = self.fail('ACT-SHEET', '开着表单按 Esc，表单没有关掉')
            elif self.where() != 'goals':
                good = self.fail('ACT-SHEET', f'Esc 关掉表单后不在目标页，而是{NAMES.get(self.where(), "认不出的画面")}')
        if good:
            return self.ok('ACT-SHEET', '目标页开着「新目标」时按 ⌘1 ⌘2 ⌘3 ⌘,，表单还在、页面不变；Esc 只关表单')
        return False

    def open_day(self, rule, files=None):
        """历史月列表 → 点第一个月份 → 月日历 → 点一个有工资的日子 → 单日详情。成功返回 True。"""
        self.key('cmd-3')
        if not self.expect(rule, 'history', '⌘3'):
            return False
        month = self.find('AXButton', r'^\d{4}年\d{1,2}月、', below=52)
        if not month:
            return self.fail(rule, '月列表里找不到月份行')
        self.click(month[0], month[1])
        header, _ = self.settle()
        if 'calendar' not in self.refs:
            if header in (self.refs['history'], self.refs['goals'], self.refs['settings']):
                return self.fail(rule, f'点月份行「{month[2].split("、")[0]}」后没进月日历')
            self.refs['calendar'] = header
            if files is not None:
                files.append(self.capture('P5-calendar'))
        elif not self.expect(rule, 'calendar', '点月份行'):
            return False
        day = self.find('AXButton', r'^\d{1,2}、¥', below=52)
        if not day:
            return self.fail(rule, '月日历里找不到有工资的日子')
        self.click(day[0], day[1])
        header, _ = self.settle()
        if 'day' not in self.refs:
            if header in (self.refs['history'], self.refs['calendar']):
                return self.fail(rule, f'点 {day[2].split("、")[0]} 日后没进单日详情')
            self.refs['day'] = header
            if files is not None:
                files.append(self.capture('P5-day-detail'))
        elif not self.expect(rule, 'day', '点日历上的一天'):
            return False
        return True

    def act_esc(self, files):
        if not self.home():
            return self.fail('ACT-ESC', '⌘1 回不到概览，没法开始')
        if not self.open_day('ACT-ESC', files):
            return False
        for step, page in (('单日详情', 'calendar'), ('月日历', 'history'), ('月列表', 'overview')):
            self.key('esc')
            if not self.visible(True, timeout=0.3) or self.where() != page:
                now = self.where() if self.state().get('visible') else '窗口已关'
                return self.fail('ACT-ESC', f'在{step}上按 Esc 应退到{NAMES[page]}，实际是{NAMES.get(now, now)}')
        self.key('esc')
        if self.visible(False):
            return self.fail('ACT-ESC', '在概览上按 Esc，窗口没有关')
        return self.ok('ACT-ESC', 'Esc 从单日详情、月日历、月列表、概览一级一级退，概览上再按才关窗')

    def act_history(self):
        if not self.home():
            return self.fail('ACT-HISTORY', '⌘1 回不到概览，没法开始')
        if not self.open_day('ACT-HISTORY'):
            return False
        self.key('cmd-1')
        if not self.expect('ACT-HISTORY', 'overview', '停在单日详情按 ⌘1'):
            return False
        self.key('cmd-3')
        if self.expect('ACT-HISTORY', 'history', '再按 ⌘3'):
            return self.ok('ACT-HISTORY', '从单日详情 ⌘1 回概览后再 ⌘3，进来的是月列表')
        return False

    def main(self):
        os.makedirs(os.path.join(self.out, 'realwindow'), exist_ok=True)
        state = self.launch()
        print(f'App 已启动 (pid {self.app.pid})，窗口 {state["width"]:.0f}×{state["height"]:.0f}，{self.screen_scale} 倍屏，前台：{state["active"]}', flush=True)
        # 启动时应在概览：辅助功能里有底栏三个入口。辅助功能树是打开后才建的，等一会儿。
        deadline = time.time() + 15
        while not self.find('AXButton', '^设置$', below=600) and time.time() < deadline:
            time.sleep(0.3)
        if not self.find('AXButton', '^设置$', below=600):
            raise Blocked('启动后不在今日概览 (假状态没生效？)，底栏的入口找不到')
        files = [self.capture('today')]
        _, self.refs['footer'] = self.settle()
        deduction = self.find('AXButton', '^今天扣钱了$')
        if not deduction:
            raise Blocked('假状态下概览上没有「今天扣钱了」，ACT-COVER 没法判断')
        self.act_push(files)
        if not all(page in self.refs for page in ('goals', 'history', 'settings')):
            raise Blocked('三页的参照没截全，后面的规则没法认页')
        self.act_dock()
        self.act_home()
        self.act_goalcard()
        self.act_cover(deduction[:2])
        self.act_sheet()
        self.act_esc(files)
        self.act_history()
        self.write_manifest(files, bool(self.state().get('active')))
        return 1 if self.failures else 0


NAMES = {'goals': '目标页', 'history': '历史月列表', 'settings': '设置页', 'calendar': '月日历', 'day': '单日详情', 'overview': '概览', 'unknown': '认不出的画面', '窗口已关': '窗口已关'}
KEYS = {'cmd-1': '⌘1', 'cmd-2': '⌘2', 'cmd-3': '⌘3', 'cmd-comma': '⌘,', 'esc': 'Esc'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--exe', required=True)
    parser.add_argument('--dylib', required=True)
    parser.add_argument('--home', required=True)
    parser.add_argument('--workdir', required=True)
    parser.add_argument('--out', required=True)
    parser.add_argument('--launch-timeout', type=float, default=60)
    args = parser.parse_args()
    run = Run(args)
    # 被 ui-checks-mac.sh 的超时或 Ctrl-C 打断时也要把自己拉起的 App 关掉。
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(2))
    try:
        code = run.main()
    except Blocked as blocked:
        print(f'BLOCKED: {blocked}', flush=True)
        code = 2
    finally:
        run.stop()
    return code


if __name__ == '__main__':
    sys.exit(main())
