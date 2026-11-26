#!/usr/bin/env python3
"""真窗口截图与交互回归：用临时目录里的假数据拉起 Debug 版 App，经注入的 harness/drive.m 在 App 进程里合成按键、点击，读窗口状态。

由 ui-checks-mac.sh 调用，不单独用：
  python3 scripts/checks/ui_drive.py --exe <App 可执行文件> --dylib <libdrive.dylib> --home <假主目录> --out <输出目录>
      [--onboarding-home <空的假主目录> --onboarding-previews <引导离屏预览目录>]
做这些事：
  1. 截真窗口图 today、P3-goals、P4-history、P5-calendar、P5-day-detail、P6-settings (2 倍，整窗含红绿灯)，写 realwindow/manifest.json。
  2. 交互回归 ACT-PUSH、ACT-HOME、ACT-ESC、ACT-SHEET、ACT-GOALCARD、ACT-DOCK、ACT-COVER、ACT-HISTORY (规则见 README)。
  3. FIT-NOSCROLL：月日历、今天扣钱了、请假 (新增、修改) 在真窗口里不用滚动；月日历同时查 FIT-CELL (每个格子里的字都在格子里)；给了 --onboarding-home 时
     用空的假主目录再起一次 App，引导两步同样量，并查 FIT-HINT (引导第 1 步的校验提示不被底部按钮栏盖住)；
     给了 --onboarding-previews 时再跑 FIT-PREVIEW (引导的离屏预览与真窗口一致)。
  每次拉起 App 都查 FONT-BUNDLED (App 实际用的字体文件在 App 包内，见 ui_font.py)。
     这一步的真窗口图放 fit/。
认页靠像素：页头区域 (窗口顶部 4–44pt、红绿灯右边) 的墨迹指纹与本次运行里 ⌘2、⌘3、⌘, 截下的参照逐像素相同；
概览靠底部入口栏 (历史、目标、设置那一条) 的指纹与启动时的参照相同。两块都避开了时钟与滚动的数字。
退出码：0 全部通过；1 有规则不过；2 blocked (窗口没出现、驱动连不上等环境问题)。
"""
import argparse, datetime, json, math, os, re, signal, socket, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ui_font  # noqa: E402
import ui_geometry  # noqa: E402

GEOMETRY = json.load(open(os.path.join(HERE, 'ui-geometry.json'), encoding='utf-8'))
# 页头区域：红绿灯右边到窗口右沿，顶部 4–44pt (概览的日期时钟从 46 起，不在里面)。
HEADER = (76, 4, 284, 40)
# 墨迹阈值：深色的字与图标；悬停时浅色的圆角底不算。
INK = 160
FOOTER_HEIGHT = 46
# FIT-NOSCROLL 的误差 (pt)。
FIT_TOLERANCE = 0.5
# FIT-PREVIEW：离屏预览与真窗口逐段比较时允许的差 (pt)，以及从哪一行比起 (避开红绿灯)。
PREVIEW_TOLERANCE = 1.0
PREVIEW_TOP = 30
# FIT-CELL：日历格子里文字的墨迹离格子上下沿至少多少 (pt)；描边 (1pt，悬停 1.5pt) 那几行不算墨迹。
CELL_MARGIN = 2.0
CELL_STROKE = 1.5
# 引导窗口的标题与 FIT-PREVIEW 比较的三个状态 (真窗口图名与离屏预览同名，见 OnboardingPreviews.swift)。
ONBOARDING_TITLE = '牛马鼓励器'
# FIT-HINT：引导第 1 步月薪空着点「下一步」时的校验提示 (WageCore 的 CommandError.salaryNotPositive)。
HINT_SALARY = '^月薪得是个正数$'


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
        height = self.state().get('height', 574)
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

    def launch(self, home=None, title='今日概览'):
        """拉起 App 并等窗口出现，再查 App 实际用的字体 (FONT-BUNDLED)。"""
        home = home or self.args.home
        env = dict(os.environ)
        env.pop('WAGETICK_DRIVE_TITLE', None)
        env.update({
            'CFFIXED_USER_HOME': home,
            'WAGETICK_FAKE_HOME': home,
            'WAGETICK_DRIVE_SOCKET': 'drive.sock',
            'WAGETICK_DRIVE_TITLE': title,
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
                self.check_font(title)
                return state
            if self.app.poll() is not None:
                raise Blocked(f'App 启动后退出了 (退出码 {self.app.returncode})，见 {self.out}/app.log')
            time.sleep(0.3)
        raise Blocked(f'{self.args.launch_timeout} 秒内{title}窗口没出现 (没有图形会话，或启动卡住了)；窗口状态：{self.state()}')

    def check_font(self, title):
        """FONT-BUNDLED：窗口出来以后 App 里界面字体、数字字体实际用的字体文件在 App 包内。"""
        code, lines = ui_font.check(self.drive.send('font'), f'真窗口 ({title})')
        for line in lines:
            print(line, flush=True)
        if code == 2:
            raise Blocked(f'真窗口 ({title}) 没取到字体报告')
        if code == 1:
            self.failures.append('FONT-BUNDLED')

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

    # MARK: 放不下 (FIT-NOSCROLL、FIT-PREVIEW)

    def fit(self, page, image):
        """当前画面里每个纵向滚动区域：内容高不超过可见高，最靠下的控件不低于滚动区域下沿 (底部按钮栏的上沿)。图存 fit/<image>.png。"""
        self.settle()
        self.snap(os.path.join(self.out, 'fit', image + '.png'))
        scrolls = [area for area in self.drive.send('scrolls')['scrolls'] if area['visible'] > 40]
        if not scrolls:
            return self.fail('FIT-NOSCROLL', f'{page}: 窗口里找不到滚动区域 (页面结构变了？)')
        elements = [e for e in self.ax() if not e.get('scroller') and e['h'] > 0 and e['role'] not in ('AXScrollArea', 'AXScrollBar')]
        good, texts = True, []
        for area in scrolls:
            top, bottom = area['y'], area['y'] + area['h']
            inside = [e['y'] + e['h'] for e in elements if top - FIT_TOLERANCE <= e['y'] < bottom]
            lowest = max(inside) if inside else top
            over = area['document'] - area['visible']
            text = f'内容高 {area["document"]:g}，可见高 {area["visible"]:g}'
            if over > FIT_TOLERANCE:
                good = self.fail('FIT-NOSCROLL', f'{page}: {text}，超出 {over:g}')
            elif lowest > bottom + FIT_TOLERANCE:
                good = self.fail('FIT-NOSCROLL', f'{page}: {text}，但最下面的控件下沿 {lowest:g} 低于底栏上沿 {bottom:g}，被盖住 {lowest - bottom:g}')
            texts.append(f'{text}，最下面的控件下沿 {lowest:g}，底栏上沿 {bottom:g}')
        if good:
            self.ok('FIT-NOSCROLL', f'{page}：' + '；'.join(texts))
        return good

    def fit_cells(self, title, image):
        """FIT-CELL：月日历每个日子格子里的字 (日号、小字、金额) 都在格子里，离上下沿至少 2pt，彼此不重叠。
        格子的框取自辅助功能树 (日子按钮，文字如「26、改班、¥952」，按「、」分开的段数就是格子里的行数)；
        墨迹在 fit/<image>.png 上量：格子中间 x+8 至 x+w-8 里与格子底色相差明显的像素 (今天的格子是深底浅字，字出了格子就看不见，所以只量格子里面)。"""
        cells = [e for e in self.ax() if e['role'] == 'AXButton' and re.search(r'^\d{1,2}(、|$)', e['label']) and e['y'] >= 52]
        if not cells:
            return self.fail('FIT-CELL', f'月日历 ({title})：辅助功能树里找不到日子格子')
        problems, crowded, tightest = [], [], None
        for cell, (lines, top, bottom, runs) in zip(cells, cell_ink(os.path.join(self.out, 'fit', image + '.png'), cells)):
            name = cell['label'].replace('、', ' ')
            y0, y1 = cell['y'], cell['y'] + cell['h']
            if top is None:
                problems.append(f'「{name}」格子 {y0:g}–{y1:g} 里没有字')
                continue
            margin = min(top - y0, y1 - bottom)
            tightest = margin if tightest is None else min(tightest, margin)
            text = f'「{name}」格子 {y0:g}–{y1:g}，墨迹 {top:g}–{bottom:g}'
            if lines >= 3:
                crowded.append(text)
            if margin < CELL_MARGIN:
                problems.append(f'{text}，离格子{"上" if top - y0 < y1 - bottom else "下"}沿只有 {margin:g}pt (要至少 {CELL_MARGIN:g})，字被格子裁掉或顶边')
            elif runs < lines:
                problems.append(f'{text}，{lines} 行字只分出 {runs} 段，有字叠在一起')
        if problems:
            return self.fail('FIT-CELL', f'月日历 ({title})：' + '；'.join(problems))
        detail = f'；三行的格子：{"；".join(crowded)}' if crowded else '；这个月没有三行的格子'
        return self.ok('FIT-CELL', f'月日历 ({title})：{len(cells)} 个格子的字都在格子里，离上下沿最少 {tightest:g}pt{detail}')

    def wait_for(self, pattern, what, role='AXButton'):
        """等辅助功能树里出现文字匹配 pattern 的元素 (最多 3 秒)，返回它的中心点；没等到是 BLOCKED。"""
        deadline = time.time() + 3
        while True:
            found = self.find(role, pattern)
            if found:
                return found
            if time.time() > deadline:
                raise Blocked(f'FIT-NOSCROLL 进不去{what}：找不到「{pattern or role}」')
            time.sleep(0.2)

    def click_button(self, pattern, what, role='AXButton'):
        found = self.wait_for(pattern, what, role)
        self.click(found[0], found[1])
        return found

    def until(self, test, what, timeout=4.0):
        """等 test() 成立 (每 0.2 秒看一次)；等不到是 BLOCKED。"""
        deadline = time.time() + timeout
        while not test():
            if time.time() > deadline:
                raise Blocked(f'FIT-NOSCROLL：{what}')
            time.sleep(0.2)
        self.settle()

    def fit_home(self):
        """⌘1 回概览：等底部入口栏的「设置」出现、页头没有标题。这一次启动换了字体，认页的指纹参照用不上，改用辅助功能树认。"""
        self.key('cmd-1')
        self.until(lambda: self.find('AXButton', '^设置$', below=self.footer_rect()[1] - 8) and not self.ax_title(), '⌘1 回不到概览')

    def fit_panel(self):
        """重新拉起今日概览窗口 (前面的交互回归留下的页面状态不带过来)，量该不滚动的页面：每个月的月日历、今天扣钱了、请假 (新增)、修改请假 (先新请一条全天的)。"""
        os.makedirs(os.path.join(self.out, 'fit'), exist_ok=True)
        self.stop()
        self.launch()
        self.fit_home()
        self.key('cmd-3')
        self.until(lambda: self.ax_title() == '历史', '⌘3 进不了历史月列表')
        months = [e for e in self.ax() if e['role'] == 'AXButton' and re.search(r'^\d{4}年\d{1,2}月、', e['label']) and e['y'] >= 52]
        if not months:
            raise Blocked('FIT-NOSCROLL：月列表里没有月份')
        most = 0
        for index, month in enumerate(months):
            title = month['label'].split('、')[0]
            self.click(month['x'] + month['w'] / 2, month['y'] + month['h'] / 2)
            self.until(lambda: self.ax_title() == title, f'点「{title}」没进月日历')
            rows = len({round(e['y']) for e in self.ax() if e['role'] == 'AXButton' and re.search(r'^\d{1,2}(、|$)', e['label']) and e['y'] >= 52})
            most = max(most, rows)
            self.fit(f'月日历 ({title}，{rows} 行)', f'calendar-{index}')
            self.fit_cells(title, f'calendar-{index}')
            self.key('esc')
            self.until(lambda: self.ax_title() == '历史', '月日历按 Esc 没回到月列表')
        if most < 6:
            self.notes.append(f'FIT-NOSCROLL：假状态里的月份最多 {most} 行，六行的月份这次没量到 (要看今天是几月)')
            print(f'note: {self.notes[-1]}', flush=True)
        self.fit_home()
        self.click_button('^今天扣钱了$', '扣钱表单')
        self.until(lambda: self.ax_title() == '今天扣钱了', '点「今天扣钱了」没打开扣钱表单')
        self.fit('今天扣钱了', 'deduction')
        # 表单开着时 ⌘1 不换页 (同 ACT-SHEET)，先按 Esc 关掉。
        self.key('esc')
        self.fit_home()
        self.click_button('^请假$', '请假表单')
        self.until(lambda: self.ax_title() == '请假', '点「请假」没打开请假表单')
        self.fit('请假 (新增)', 'leave-request')
        self.click_button('^就这么请', '新请一条')
        self.fit_home()
        self.click_button('请假、扣薪', '修改请假')
        self.until(lambda: self.ax_title() == '修改请假', '点概览上的请假没打开修改请假')
        self.fit('修改请假', 'leave-edit')
        # 新请的那条留在临时目录的假状态里，这是这次启动的最后一步，不再撤销。
        self.key('esc')

    def fit_onboarding(self):
        """用空的假主目录再起一次 App (没有 state.json 就打开引导窗口)：引导第 1 步月薪空、日薪已填，第 2 步饭点开、关。"""
        self.stop()
        state = self.launch(home=self.args.onboarding_home, title=ONBOARDING_TITLE)
        print(f'引导窗口已打开 (pid {self.app.pid})，{state["width"]:.0f}×{state["height"]:.0f}', flush=True)
        deadline = time.time() + 15
        while not self.find('AXButton', '^下一步$') and time.time() < deadline:
            time.sleep(0.3)
        if not self.find('AXButton', '^下一步$'):
            raise Blocked('FIT-NOSCROLL：空主目录下打开的不是引导第 1 步 (找不到「下一步」)')
        self.settle()
        self.fit('引导第 1 步 (月薪、空)', 'P1-1-salary-empty')
        self.click_button('^日薪$', '日薪')
        self.click_button('', '工资输入框', role='AXTextField')
        self.drive.send('text 200')
        self.fit('引导第 1 步 (日薪、已填)', 'P1-1-salary-daily')
        self.click_button('^月薪$', '月薪')
        self.click_button('', '工资输入框', role='AXTextField')
        self.drive.send('clear')
        self.fit_hint()
        self.click_button('', '工资输入框', role='AXTextField')
        self.drive.send('text 20000')
        self.click_button('^下一步$', '引导第 2 步')
        self.wait_for('^开始搬砖', '引导第 2 步')
        self.fit('引导第 2 步 (饭点打开)', 'P1-2-schedule')
        self.click_button('^饭点$', '饭点开关', role='AXCheckBox')
        self.fit('引导第 2 步 (饭点关闭)', 'P1-2-schedule-nolunch')

    def fit_hint(self):
        """FIT-HINT：引导第 1 步工资空着点「下一步」，校验提示整行露在滚动区域里 (不被底部按钮栏盖住)。"""
        self.click_button('^下一步$', '下一步')
        hint = HINT_SALARY
        deadline = time.time() + 3
        while not self.find('AXStaticText', hint) and time.time() < deadline:
            time.sleep(0.2)
        self.settle()
        self.snap(os.path.join(self.out, 'fit', 'P1-1-salary-hint.png'))
        found = [e for e in self.ax() if e['role'] == 'AXStaticText' and re.search(hint, e['label'] + e['value'])]
        if not found:
            return self.fail('FIT-HINT', f'引导第 1 步工资空着点「下一步」，没出现校验提示「{hint}」')
        scrolls = [area for area in self.drive.send('scrolls')['scrolls'] if area['visible'] > 40]
        if not scrolls:
            return self.fail('FIT-HINT', '引导第 1 步找不到滚动区域 (页面结构变了？)')
        area = max(scrolls, key=lambda a: a['h'])
        top, bottom = area['y'], area['y'] + area['h']
        e = found[0]
        if e['y'] < top - FIT_TOLERANCE or e['y'] + e['h'] > bottom + FIT_TOLERANCE:
            return self.fail('FIT-HINT', f'引导第 1 步的校验提示在 {e["y"]:g}–{e["y"] + e["h"]:g}，露出来的只有 {top:g}–{bottom:g} (底部按钮栏上沿 {bottom:g})，被盖住了')
        return self.ok('FIT-HINT', f'引导第 1 步的校验提示在 {e["y"]:g}–{e["y"] + e["h"]:g}，整行在 {top:g}–{bottom:g} 里 (底部按钮栏上沿 {bottom:g})')

    def fit_preview(self):
        """引导三个状态的离屏预览与真窗口图逐段比较：每一段内容 (非底色的连续行) 的上下沿相差不超过 1pt。"""
        good, worst = True, 0.0
        for name in ('P1-1-salary-empty', 'P1-1-salary-daily', 'P1-2-schedule'):
            preview = os.path.join(self.args.onboarding_previews, name + '.png')
            real = os.path.join(self.out, 'fit', name + '.png')
            a, b = content_spans(preview), content_spans(real)
            if len(a) != len(b):
                good = self.fail('FIT-PREVIEW', f'{name}: 离屏预览分 {len(a)} 段、真窗口 {len(b)} 段 (预览 {fmt_spans(a)}；真窗口 {fmt_spans(b)})')
                continue
            diff = max((max(abs(x[0] - y[0]), abs(x[1] - y[1])) for x, y in zip(a, b)), default=0)
            worst = max(worst, diff)
            if diff > PREVIEW_TOLERANCE:
                good = self.fail('FIT-PREVIEW', f'{name}: 离屏预览与真窗口相差 {diff:g}pt (预览 {fmt_spans(a)}；真窗口 {fmt_spans(b)})')
        if good:
            self.ok('FIT-PREVIEW', f'引导 3 个状态的离屏预览与真窗口逐段一致 (最大差 {worst:g}pt)')
        return good

    def main(self):
        os.makedirs(os.path.join(self.out, 'realwindow'), exist_ok=True)
        state = self.launch()
        print(f'App 已启动 (pid {self.app.pid})，窗口 {state["width"]:.0f}×{state["height"]:.0f}，{self.screen_scale} 倍屏，前台：{state["active"]}', flush=True)
        # 启动时应在概览：辅助功能里有底栏三个入口。辅助功能树是打开后才建的，等一会儿。
        deadline = time.time() + 15
        while not self.find('AXButton', '^设置$', below=self.footer_rect()[1] - 8) and time.time() < deadline:
            time.sleep(0.3)
        if not self.find('AXButton', '^设置$', below=self.footer_rect()[1] - 8):
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
        self.fit_panel()
        if self.args.onboarding_home:
            self.fit_onboarding()
            if self.args.onboarding_previews:
                self.fit_preview()
        return 1 if self.failures else 0


def cell_ink(path, cells):
    """每个格子里字的墨迹：(行数、墨迹上沿、墨迹下沿、墨迹分成几段)，单位 pt，相对窗口左上角；格子里没有墨迹时上下沿为 None。
    底色取格子左边 2.5pt、半高处；只看 x+8 至 x+w-8 (避开圆角与左右描边)，上下各去掉描边的 1.5pt。"""
    width, height, rows, pixel = ui_geometry.load_png(path)
    scale = width / 360
    result = []
    for cell in cells:
        x, y, w, h = cell['x'], cell['y'], cell['w'], cell['h']
        fill = pixel(int((x + 2.5) * scale), int((y + h / 2) * scale))
        x0, x1 = int((x + 8) * scale), int((x + w - 8) * scale)
        first, last = int(math.ceil((y + CELL_STROKE) * scale)), int((y + h - CELL_STROKE) * scale)
        flags = [any(sum(abs(c - d) for c, d in zip(pixel(px, py), fill)) > 60 for px in range(x0, x1))
                 for py in range(first, min(last, rows))]
        spans = ui_geometry.runs(flags, 0)
        lines = len(cell['label'].split('、'))
        if not spans:
            result.append((lines, None, None, 0))
            continue
        result.append((lines, (first + spans[0][0]) / scale, (first + spans[-1][1] + 1) / scale, len(spans)))
    return result


def content_spans(path):
    """图里内容的纵向分段 (pt)：从 PREVIEW_TOP 起，x 24–336pt 里有非底色像素的连续行并成一段。底色取左边 4pt 处。"""
    width, height, rows, pixel = ui_geometry.load_png(path)
    scale = width / 360
    background = pixel(int(4 * scale), int(300 * scale))
    x0, x1, step = int(24 * scale), int(336 * scale), max(1, int(scale))
    flags = []
    for y in range(int(PREVIEW_TOP * scale), rows):
        flags.append(any(sum(abs(c - d) for c, d in zip(pixel(x, y), background)) > 12 for x in range(x0, x1, step)))
    return [((start + PREVIEW_TOP * scale) / scale, (end + 1 + PREVIEW_TOP * scale) / scale) for start, end in ui_geometry.runs(flags, 0)]


def fmt_spans(spans):
    return ' '.join(f'{a:g}–{b:g}' for a, b in spans)


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
    parser.add_argument('--onboarding-home', help='空的假主目录：给了就再起一次 App 量引导两步 (FIT-NOSCROLL)')
    parser.add_argument('--onboarding-previews', help='引导的离屏预览目录：给了就比较预览与真窗口 (FIT-PREVIEW)')
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
