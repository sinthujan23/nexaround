"""Line-art sketches of world landmarks as SVG fragments.

Each function returns (width, height, inner_svg) in its own coordinate box; the
ground sits on y = height. Strokes are left to the caller (stroke=currentColor).
"""
import math

def _pl(pts, close=False):
    d = "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in pts)
    return f'<path d="{d}{" Z" if close else ""}"/>'

def _line(x1, y1, x2, y2):
    return f'<path d="M{x1:.1f},{y1:.1f} L{x2:.1f},{y2:.1f}"/>'

def _rect(x, y, w, h):
    return f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}"/>'

def _lerp_leg(pts, y):
    for (x1, y1), (x2, y2) in zip(pts, pts[1:]):
        if min(y1, y2) <= y <= max(y1, y2):
            t = (y - y1) / (y2 - y1) if y2 != y1 else 0
            return x1 + (x2 - x1) * t
    return pts[-1][0]

def _ground(w, h, pad=0.12):
    return _line(-w * pad, h, w * (1 + pad), h)

# --------------------------------------------------------------------------
def eiffel():
    W, H = 200, 520
    L = [(8, 520), (36, 400), (66, 262), (86, 150), (95, 62)]
    R = [(W - x, y) for x, y in L]
    Li = [(56, 520), (58, 408)]
    Ri = [(W - x, y) for x, y in Li]
    s = [_pl(L), _pl(R), _pl(Li), _pl(Ri)]
    s += [_rect(24, 392, 152, 16), _rect(56, 254, 88, 12), _rect(80, 144, 40, 10), _rect(91, 52, 18, 10)]
    s += [_line(100, 52, 100, 0), _line(96, 30, 104, 30)]
    s.append('<path d="M56,520 Q100,440 144,520"/>')
    # leg lattice below first floor
    for y1, y2 in ((520, 480), (480, 440), (440, 408)):
        s.append(_line(_lerp_leg(L, y1), y1, _lerp_leg(Li, y2) if y2 >= 408 else 58, y2))
        s.append(_line(W - _lerp_leg(L, y1), y1, W - (_lerp_leg(Li, y2) if y2 >= 408 else 58), y2))
    def X(ya, yb):
        la, lb = _lerp_leg(L, ya), _lerp_leg(L, yb)
        s.append(_line(la, ya, W - lb, yb)); s.append(_line(W - la, ya, lb, yb))
    for ya, yb in ((392, 330), (330, 266)): X(ya, yb)
    for ya, yb in ((254, 204), (204, 154)): X(ya, yb)
    for ya, yb in ((144, 104), (104, 62)): X(ya, yb)
    s.append(_ground(W, H))
    return W, H, "".join(s)

def pisa():
    W, H = 150, 390
    s = []
    # ground floor blind arches
    s += [_line(25, 390, 25, 72), _line(125, 390, 125, 72)]
    for i in range(4):
        x0 = 25 + i * 25
        s.append(f'<path d="M{x0+4},390 L{x0+4},328 Q{x0+12.5},310 {x0+21},328 L{x0+21},390"/>')
    y = 300
    for g in range(6):
        s.append(_line(19, y, 131, y))
        top = y - 38
        for i in range(5):
            x0 = 25 + i * 20
            s.append(f'<path d="M{x0+4},{y} L{x0+4},{top+15} Q{x0+10},{top+5} {x0+16},{top+15} L{x0+16},{y}"/>')
        y = top
    s.append(_line(19, y, 131, y))
    # belfry
    s += [_line(38, 72, 38, 30), _line(112, 72, 112, 30), '<path d="M34,30 Q75,12 116,30 Z"/>']
    for i in range(4):
        x0 = 38 + i * 18.5
        s.append(f'<path d="M{x0+4},70 L{x0+4},46 Q{x0+9},38 {x0+14},46 L{x0+14},70"/>')
    g = f'<g transform="rotate(5.5 75 390)">{"".join(s)}</g>'
    return W, H, g + _ground(W, H, .35)

def colosseum():
    W, H = 440, 210
    s = []
    s.append('<path d="M0,210 Q-9,120 0,30 L250,30 L258,48 L262,66 L300,66 L306,90 L310,112 L350,112 L356,138 L360,160 L440,160 L440,210"/>')
    s += [_line(0, 66, 262, 66), _line(0, 112, 310, 112), _line(0, 160, 360, 160)]
    for i in range(15):
        x = i * 29 + 2
        s.append(f'<path d="M{x+5},210 L{x+5},184 Q{x+14},168 {x+23},184 L{x+23},210"/>')
    for i in range(12):
        x = i * 29 + 2
        s.append(f'<path d="M{x+5},160 L{x+5},136 Q{x+14},121 {x+23},136 L{x+23},160"/>')
    for i in range(10):
        x = i * 29 + 2
        s.append(f'<path d="M{x+5},112 L{x+5},90 Q{x+14},76 {x+23},90 L{x+23},112"/>')
    for i in range(0, 8, 2):
        x = i * 29 + 2
        s.append(_rect(x + 10, 42, 9, 12))
    # broken inner ring
    s += ['<path d="M270,66 L282,40 L296,58 L312,36 L330,62"/>', '<path d="M318,112 L334,92 L350,104"/>']
    s.append(_ground(W, H, .06))
    return W, H, "".join(s)

def big_ben():
    W, H = 100, 480
    s = [_line(20, 480, 20, 175), _line(80, 480, 80, 175)]
    for x in (32, 44, 56, 68):
        s.append(_line(x, 186, x, 470))
    for y in (262, 342, 420):
        s.append(_line(20, y, 80, y))
    s.append(_rect(12, 104, 76, 72))
    s += ['<circle cx="50" cy="140" r="27"/>', '<circle cx="50" cy="140" r="21"/>', _line(50, 140, 50, 124), _line(50, 140, 62, 147)]
    s += [_rect(18, 70, 64, 34)]
    for i in range(3):
        x0 = 24 + i * 18
        s.append(f'<path d="M{x0+2},100 L{x0+2},84 Q{x0+7},76 {x0+12},84 L{x0+12},100"/>')
    s += ['<path d="M12,70 L30,40 L50,4 L70,40 L88,70"/>', _rect(32, 40, 36, 12), _line(50, 4, 50, -14), _line(45, -8, 55, -8)]
    s += [_line(12, 70, 12, 50), _line(88, 70, 88, 50), _line(50, 40, 50, 12)]
    s.append(_ground(W, H, .5))
    return W, H, "".join(s)

def taj_mahal():
    W, H = 440, 280
    s = [_rect(40, 262, 360, 18), _rect(120, 150, 200, 112), _rect(185, 165, 70, 97)]
    s.append('<path d="M193,262 L193,202 Q193,178 220,168 Q247,178 247,202 L247,262"/>')
    for x0 in (138, 268):
        for y0 in (166, 212):
            s.append(f'<path d="M{x0},{y0+42} L{x0},{y0+16} Q{x0},{y0+4} {x0+17},{y0} Q{x0+34},{y0+4} {x0+34},{y0+16} L{x0+34},{y0+42}"/>')
    s.append(_rect(170, 135, 100, 15))
    s.append('<path d="M168,135 C148,90 176,62 200,49 C211,42 217,31 220,18 C223,31 229,42 240,49 C264,62 292,90 272,135"/>')
    s += [_line(220, 18, 220, -2), '<circle cx="220" cy="8" r="3"/>']
    for cx in (142, 298):
        s += [_rect(cx - 14, 138, 28, 12), f'<path d="M{cx-16},138 Q{cx},110 {cx+16},138"/>', _line(cx, 118, cx, 108)]
    for x in (40, 386):
        s.append(_rect(x, 72, 14, 190))
        for y in (122, 172, 222):
            s.append(_line(x - 5, y, x + 19, y))
        s += [f'<path d="M{x-5},72 Q{x+7},48 {x+19},72"/>', _line(x + 7, 54, x + 7, 42)]
    s.append(_ground(W, H, .04))
    return W, H, "".join(s)

def liberty():
    W, H = 150, 470
    s = [_rect(0, 450, 150, 20), _rect(30, 332, 90, 118), _rect(24, 322, 102, 10), _line(30, 360, 120, 360)]
    s += [_rect(52, 380, 12, 26), _rect(86, 380, 12, 26)]
    s += ['<path d="M50,322 C45,262 47,205 56,172"/>', '<path d="M100,322 C105,262 101,205 93,172"/>', '<path d="M56,172 Q74,160 93,172"/>']
    s += ['<path d="M64,205 Q67,262 62,320"/>', '<path d="M80,195 Q85,262 82,320"/>']
    s.append('<circle cx="74" cy="148" r="11"/>')
    for k in range(7):
        a = math.radians(-160 + k * 23.3)
        s.append(_line(74 + 12 * math.cos(a), 148 + 12 * math.sin(a), 74 + 24 * math.cos(a), 148 + 24 * math.sin(a)))
    s += [_line(60, 172, 50, 62), _line(69, 168, 60, 62), _rect(48, 50, 13, 12), '<path d="M50,50 Q45,34 55,20 Q65,34 59,50"/>']
    s.append('<path d="M95,182 L110,188 L104,234 L89,228 Z"/>')
    s.append(_ground(W, H, .25))
    return W, H, "".join(s)

def opera_house():
    W, H = 420, 170
    s = [_rect(0, 148, 420, 22), _line(0, 158, 420, 158)]
    def sail(a, w, yp, flip=False):
        if not flip:
            d = f"M{a},148 C{a+w*0.05},{yp+60} {a+w*0.35},{yp+8} {a+w*0.9},{yp} C{a+w*0.72},{yp+46} {a+w*0.8},{108} {a+w},148"
            rib = f"M{a+w*0.9},{yp} Q{a+w*0.55},{yp+50} {a+w*0.55},148"
        else:
            d = f"M{a+w},148 C{a+w*0.95},{yp+60} {a+w*0.65},{yp+8} {a+w*0.1},{yp} C{a+w*0.28},{yp+46} {a+w*0.2},{108} {a},148"
            rib = f"M{a+w*0.1},{yp} Q{a+w*0.45},{yp+50} {a+w*0.45},148"
        return f'<path d="{d}"/><path d="{rib}"/>'
    s += [sail(10, 120, 48, True), sail(70, 120, 22, True), sail(140, 70, 70), sail(200, 130, 30, True), sail(262, 120, 6, True), sail(340, 70, 64)]
    s.append(_ground(W, H, .04))
    return W, H, "".join(s)

def pyramids():
    W, H = 440, 220
    s = [_pl([(0, 220), (150, 30), (300, 220)]), _line(150, 30, 196, 220)]
    for k in range(1, 8):
        t = k / 8
        y = 30 + 190 * t
        s.append(_line(150 - 150 * t, y, 150 + 46 * t, y))
    s += [_pl([(250, 220), (345, 96), (440, 220)]), _line(345, 96, 372, 220)]
    for k in range(1, 5):
        t = k / 5
        y = 96 + 124 * t
        s.append(_line(345 - 95 * t, y, 345 + 27 * t, y))
    s.append('<path d="M-30,220 Q60,206 150,220 Q260,232 470,214"/>')
    return W, H, "".join(s)

def burj_khalifa():
    W, H = 110, 600
    L = [(4, 600), (4, 520), (14, 520), (14, 430), (22, 430), (22, 340), (30, 340), (30, 252), (38, 252), (38, 172), (44, 172), (44, 104), (50, 104), (52, 40), (55, 0)]
    R = [(106, 600), (106, 560), (96, 560), (96, 470), (88, 470), (88, 380), (80, 380), (80, 292), (72, 292), (72, 212), (66, 212), (66, 142), (60, 142), (58, 40), (55, 0)]
    s = [_pl(L), _pl(R), _line(55, 600, 55, 60)]
    for y in (560, 470, 380, 292, 212, 142):
        s.append(_line(_lerp_leg(L, y + 1), y, _lerp_leg(R, y + 1), y))
    s.append(_ground(W, H, .5))
    return W, H, "".join(s)

def petronas():
    W, H = 180, 520
    s = []
    for cx in (45, 135):
        s += [_line(cx - 25, 520, cx - 25, 160), _line(cx + 25, 520, cx + 25, 160)]
        for dx in (-12, 0, 12):
            s.append(_line(cx + dx, 170, cx + dx, 515))
        s += [_pl([(cx - 25, 160), (cx - 20, 160), (cx - 20, 120), (cx - 15, 120), (cx - 15, 92), (cx - 10, 92), (cx - 10, 72), (cx - 4, 72), (cx, 6),
                   (cx + 4, 72), (cx + 10, 72), (cx + 10, 92), (cx + 15, 92), (cx + 15, 120), (cx + 20, 120), (cx + 20, 160), (cx + 25, 160)])]
        for y in (160, 120, 92, 72):
            s.append(_line(cx - 25 + (160 - y) / 8, y, cx + 25 - (160 - y) / 8, y))
    s += [_rect(70, 292, 40, 10), _line(76, 302, 70, 340), _line(104, 302, 110, 340)]
    s.append(_ground(W, H, .3))
    return W, H, "".join(s)

def christ_redeemer():
    W, H = 300, 380
    s = ['<path d="M-20,380 C50,336 96,302 130,292 L170,292 C204,302 250,336 320,380"/>', _rect(138, 262, 24, 30)]
    s.append('<path d="M40,131 L128,126 L144,124 L156,124 L172,126 L260,131 L260,139 L172,142 L160,150 L162,262 L138,262 L140,150 L128,142 L40,139 Z"/>')
    s += ['<circle cx="150" cy="111" r="10"/>', _line(150, 152, 150, 258), _line(144, 160, 142, 256)]
    return W, H, "".join(s)

def space_needle():
    W, H = 140, 520
    s = ['<path d="M30,520 C52,380 62,280 54,200 L50,150"/>', '<path d="M110,520 C88,380 78,280 86,200 L90,150"/>', _line(70, 520, 70, 150)]
    s += ['<path d="M60,520 C66,400 70,300 66,200"/>', '<path d="M80,520 C74,400 70,300 74,200"/>']
    s.append('<path d="M2,140 L138,140 L118,118 L22,118 Z"/>')
    s += [_line(22, 129, 118, 129), _rect(46, 150, 48, 4), '<path d="M42,118 Q70,96 98,118"/>', _line(70, 104, 70, 20), _line(66, 60, 74, 60)]
    s.append(_line(54, 330, 86, 330))
    s.append(_ground(W, H, .25))
    return W, H, "".join(s)

def golden_gate():
    W, H = 480, 220
    s = [_line(-20, 140, 500, 140), _line(-20, 148, 500, 148)]
    for tx in (130, 350):
        s += [_line(tx - 10, 214, tx - 10, 22), _line(tx + 10, 214, tx + 10, 22)]
        for y in (22, 52, 86, 120):
            s.append(_line(tx - 12, y, tx + 12, y))
    s += ['<path d="M-20,128 Q60,110 130,24"/>', '<path d="M130,24 Q240,168 350,24"/>', '<path d="M350,24 Q420,110 500,128"/>']
    for x in range(150, 340, 16):
        t = (x - 130) / 220
        y = (1 - t) ** 2 * 24 + 2 * (1 - t) * t * 168 + t * t * 24
        s.append(_line(x, y, x, 140))
    s.append('<path d="M-20,214 Q40,206 100,214 T220,214 T340,214 T500,214"/>')
    return W, H, "".join(s)

LANDMARKS = {
    "eiffel": eiffel, "pisa": pisa, "colosseum": colosseum, "big_ben": big_ben, "taj_mahal": taj_mahal,
    "liberty": liberty, "opera_house": opera_house, "pyramids": pyramids, "burj_khalifa": burj_khalifa,
    "petronas": petronas, "christ_redeemer": christ_redeemer, "space_needle": space_needle, "golden_gate": golden_gate,
}

def place(name, x, y_bottom, height=None, width=None, color="#fff", opacity=.2, sw=3.0, flt=""):
    """SVG <g> for a landmark whose box bottom-left sits at (x, y_bottom)."""
    W, H, inner = LANDMARKS[name]()
    k = (height / H) if height else (width / W)
    return (f'<g transform="translate({x:.1f},{y_bottom - H * k:.1f}) scale({k:.4f})" fill="none" stroke="{color}" '
            f'stroke-opacity="{opacity}" stroke-width="{sw / k:.2f}" stroke-linecap="round" stroke-linejoin="round"{flt}>{inner}</g>')
