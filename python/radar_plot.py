#!/usr/bin/env python3
"""Live BGT60 radar plots: distance, speed, angle, and a plan-position indicator.

UART line: S,<seq>,<dist_cm>,<speed_cms>,<angle_x10>,<flags>

One window. The time-history axis is fixed: the left edge is five seconds ago
(t-5 s) and the right edge is the present (t). Samples scroll left as wall
time advances while the FPGA keeps sending.

The plan-position indicator sits beside the time plots. The radar is at the
center. Range is distance in centimetres. 0° is straight ahead; positive
azimuth is to the right. The FPGA reports arcsin azimuth, so only the front
half (±90°) is drawn.
"""
from __future__ import annotations

import argparse
import collections
import math
import sys
import threading
import time

WINDOW_S = 5.0
# Fastest telemetry spacing: TELEM_WAIT is 500_000 clocks at 100 MHz.
MIN_PERIOD_S = 0.005
# Distance subplot spans 30–110 cm; leave a little room past that ring.
PPI_RMAX_CM = 120.0


def parse_line(line: str):
    line = line.strip()
    if not line.startswith("S,"):
        return None
    parts = line.split(",")
    if len(parts) < 6:
        return None
    try:
        seq = int(parts[1])
        dist_cm = float(parts[2])
        speed_ms = float(parts[3]) / 100.0
        angle_deg = float(parts[4]) / 10.0
        flags = int(parts[5])
    except ValueError:
        return None
    valid = bool(flags & 1)
    return seq, dist_cm, speed_ms, angle_deg, valid


class Timeline:
    """Stamp a UART burst so the newest sample sits at arrival time.

    Several lines often arrive in one serial read. They are spaced backward
    from that instant by the measured sample period so they do not stack
    on a single x position. Timestamps are never rewritten later; the plot
    scrolls because x = timestamp - now.
    """

    def __init__(self, period: float = MIN_PERIOD_S):
        self.period = period
        self.last_seq = None
        self.last_ts = None
        self.last_arrival = None

    def add(self, samples, now: float):
        if not samples:
            return []
        if self.last_seq is not None and self.last_arrival is not None:
            dseq = (samples[-1][0] - self.last_seq) & 0xFFFF
            elapsed = now - self.last_arrival
            if 0 < dseq < 2000 and 0 < elapsed < 5.0:
                measured = elapsed / dseq
                if MIN_PERIOD_S <= measured <= 0.5:
                    self.period = 0.8 * self.period + 0.2 * measured

        n = len(samples)
        if self.last_ts is None or self.last_seq is None:
            times = [now - (n - 1 - i) * self.period for i in range(n)]
        else:
            dseq_first = (samples[0][0] - self.last_seq) & 0xFFFF
            if dseq_first == 0 or dseq_first > 5000:
                dseq_first = 1
            start = self.last_ts + dseq_first * self.period
            times = [start + i * self.period for i in range(n)]
            if times[-1] > now or now - times[-1] > 0.2:
                times = [now - (n - 1 - i) * self.period for i in range(n)]
                if times[0] <= self.last_ts:
                    span = now - self.last_ts
                    if span <= 0:
                        times = [now for _ in range(n)]
                    else:
                        times = [self.last_ts + span * (i + 1) / n for i in range(n)]

        if times[-1] > now:
            shift = times[-1] - now
            times = [t - shift for t in times]

        out = []
        for ts, sample in zip(times, samples):
            _seq, dist, speed, angle, valid = sample
            if not valid:
                dist = speed = angle = float("nan")
            out.append((ts, dist, speed, angle))
        self.last_seq = samples[-1][0]
        self.last_ts = out[-1][0]
        self.last_arrival = now
        return out


def samples_in_window(buf, now: float):
    """Map absolute timestamps onto [-WINDOW_S, 0], 0 = present."""
    xs, dist, speed, angle = [], [], [], []
    for ts, d, s, a in buf:
        x = ts - now
        if x < -WINDOW_S:
            continue
        if x > 0.0:
            x = 0.0
        xs.append(x)
        dist.append(d)
        speed.append(s)
        angle.append(a)
    return xs, dist, speed, angle


def configure_ppi(ax):
    """Front half only: 0° ahead, +angle to the right, ±90° at the sides.

    Azimuth is arcsin(Δφ/π), so the FPGA never reports the rear half.
    """
    ax.set_theta_zero_location("N")
    ax.set_theta_direction(-1)
    ax.set_thetalim(-math.pi / 2, math.pi / 2)
    ax.set_rlim(0.0, PPI_RMAX_CM)
    ax.set_rticks([40, 80, 120])
    ax.set_rlabel_position(0)
    ax.set_title("PPI  front ±90°\n0° ahead,  + to the right,  cm", pad=8)
    ax.grid(True, alpha=0.4)
    ax.plot(0, 0, "o", color="black", ms=6, zorder=5)


def ppi_blips(angles, dists, ages):
    """Return (theta_rad, range_cm, rgba) for finite angle/distance samples."""
    pts = []
    cols = []
    for angle, dist, age in zip(angles, dists, ages):
        if angle != angle or dist != dist:
            continue
        pts.append((math.radians(angle), dist))
        alpha = 0.25 + 0.75 * max(0.0, min(1.0, age))
        cols.append((0.12, 0.47, 0.71, alpha))
    return pts, cols


def apply_ppi(scatter, head, spoke, angles, dists, ages):
    pts, cols = ppi_blips(angles, dists, ages)
    if pts:
        scatter.set_offsets(pts)
        scatter.set_facecolors(cols)
        scatter.set_sizes([18] * len(pts))
        last = pts[-1]
        head.set_offsets([last])
        head.set_sizes([70])
        spoke.set_data([last[0], last[0]], [0.0, PPI_RMAX_CM])
    else:
        scatter.set_offsets([(0.0, 0.0)])
        scatter.set_facecolors([(0, 0, 0, 0)])
        scatter.set_sizes([0])
        head.set_offsets([(0.0, 0.0)])
        head.set_sizes([0])
        spoke.set_data([], [])


def lock_time_scales(axes):
    """Fixed scales so a sample is drawn at its real m/s and degrees."""
    axes[0].set_ylim(30, 110)
    axes[1].set_ylim(-80, 80)
    axes[1].set_yticks([-80, -40, 0, 40, 80])
    axes[2].set_ylim(-90, 90)
    axes[2].set_yticks([-90, -45, 0, 45, 90])
    for ax in axes:
        ax.set_autoscaley_on(False)


def set_window_title(fig, title: str):
    try:
        fig.canvas.manager.set_window_title(title)
    except Exception:
        pass


def make_dashboard():
    """One window: time history on the left, front-half PPI on the right."""
    import matplotlib.pyplot as plt

    fig = plt.figure(figsize=(11.5, 6.4))
    gs = fig.add_gridspec(
        3, 2,
        width_ratios=(1.45, 1.0),
        left=0.07, right=0.98, top=0.88, bottom=0.09,
        wspace=0.35, hspace=0.18,
    )
    ax0 = fig.add_subplot(gs[0, 0])
    ax1 = fig.add_subplot(gs[1, 0], sharex=ax0)
    ax2 = fig.add_subplot(gs[2, 0], sharex=ax0)
    ppi_ax = fig.add_subplot(gs[:, 1], projection="polar")
    configure_ppi(ppi_ax)
    ppi_sc = ppi_ax.scatter([], [], s=18, linewidths=0, zorder=3)
    ppi_hd = ppi_ax.scatter([], [], s=70, c="#d62728", linewidths=0, zorder=4)
    (ppi_spoke,) = ppi_ax.plot([], [], color="#d62728", lw=1.0, alpha=0.55, zorder=2)
    set_window_title(fig, "Radar")
    return fig, (ax0, ax1, ax2), (ppi_sc, ppi_hd, ppi_spoke)


def choose_port(explicit: str | None) -> str:
    if explicit:
        return explicit
    try:
        from serial.tools import list_ports
    except ImportError:
        print("pyserial is required: pip install pyserial matplotlib", file=sys.stderr)
        sys.exit(1)
    ports = list(list_ports.comports())
    if not ports:
        print("No serial ports found. Plug in the Basys3 USB-UART and run again.", file=sys.stderr)
        sys.exit(1)

    def score(p):
        text = " ".join(
            filter(None, [p.device, p.description, p.manufacturer, p.hwid])
        ).lower()
        value = 0
        if "ftdi" in text or "ft232" in text:
            value += 3
        if "usb serial" in text or "uart" in text:
            value += 2
        if "basys" in text:
            value += 4
        return value

    ports.sort(key=score, reverse=True)
    chosen = ports[0]
    print(f"Using {chosen.device} ({chosen.description})")
    if len(ports) > 1:
        print("Other ports (pass --port COMx to override):")
        for p in ports[1:]:
            print(f"  {p.device}: {p.description}")
    return chosen.device


def replay_file(path: str):
    import matplotlib.pyplot as plt

    ts, d, s, a = [], [], [], []
    t0 = None
    with open(path, "r", encoding="utf-8") as f:
        for i, line in enumerate(f):
            parsed = parse_line(line)
            if parsed is None:
                continue
            _seq, dist_cm, speed_ms, angle_deg, valid = parsed
            if not valid:
                continue
            t = i * MIN_PERIOD_S
            if t0 is None:
                t0 = t
            ts.append(t - t0)
            d.append(dist_cm)
            s.append(speed_ms)
            a.append(angle_deg)
    fig, axes, (ppi_sc, ppi_hd, ppi_spoke) = make_dashboard()
    axes[0].plot(ts, d)
    axes[0].set_ylabel("Distance (cm)")
    axes[1].plot(ts, s)
    axes[1].set_ylabel("Speed (m/s)")
    axes[2].plot(ts, a)
    axes[2].set_ylabel("Angle (deg)")
    axes[2].set_xlabel("Time (s)")
    lock_time_scales(axes)
    for ax in axes:
        ax.grid(True, alpha=0.3)
    n = len(ts)
    ages = [(i + 1) / n for i in range(n)] if n else []
    apply_ppi(ppi_sc, ppi_hd, ppi_spoke, a, d, ages)
    fig.suptitle("radar_bgt_c replay")
    plt.show()


def live_plot(port: str, baud: int):
    try:
        import serial
    except ImportError:
        print("pyserial is required: pip install pyserial matplotlib", file=sys.stderr)
        sys.exit(1)
    import matplotlib.pyplot as plt
    from matplotlib.animation import FuncAnimation

    try:
        ser = serial.Serial(port, baudrate=baud, timeout=0.02)
    except serial.SerialException as exc:
        print(f"Could not open {port}: {exc}", file=sys.stderr)
        sys.exit(1)

    buf = collections.deque()
    lock = threading.Lock()
    stop = threading.Event()
    timeline = Timeline()
    stats = {"lines": 0}

    def reader():
        leftover = ""
        while not stop.is_set():
            try:
                chunk = ser.read(4096)
            except (serial.SerialException, OSError):
                break
            if not chunk:
                continue
            leftover += chunk.decode("ascii", errors="ignore")
            if len(leftover) > 65536:
                leftover = leftover[-4096:]
            batch = []
            while "\n" in leftover:
                line, leftover = leftover.split("\n", 1)
                parsed = parse_line(line)
                if parsed is not None:
                    batch.append(parsed)
            if not batch:
                continue
            stamped = timeline.add(batch, time.time())
            with lock:
                buf.extend(stamped)
                stats["lines"] += len(stamped)

    thread = threading.Thread(target=reader, name="uart-reader", daemon=True)
    thread.start()

    fig, axes, (ppi_sc, ppi_hd, ppi_spoke) = make_dashboard()
    (ln0,) = axes[0].plot([], [], linewidth=1.4)
    (ln1,) = axes[1].plot([], [], linewidth=1.4)
    (ln2,) = axes[2].plot([], [], linewidth=1.4)
    axes[0].set_ylabel("Distance (cm)")
    axes[1].set_ylabel("Speed (m/s)")
    axes[2].set_ylabel("Angle (deg)")
    lock_time_scales(axes)
    axes[2].set_xlim(-WINDOW_S, 0.0)
    axes[2].set_xticks([-5, -4, -3, -2, -1, 0])
    axes[2].set_xticklabels(["t-5s", "t-4s", "t-3s", "t-2s", "t-1s", "t"])
    axes[2].set_xlabel("time  (left = 5 s ago,  right = now)")
    for ax in axes:
        ax.set_autoscalex_on(False)
        ax.set_autoscaley_on(False)
        ax.grid(True, alpha=0.3)
    title = fig.suptitle(f"waiting for radar data    {port} @ {baud}")

    def update(_frame):
        now = time.time()
        with lock:
            cutoff = now - WINDOW_S
            while buf and buf[0][0] < cutoff:
                buf.popleft()
            xs, dist, speed, angle = samples_in_window(buf, now)
            received = stats["lines"]
        ln0.set_data(xs, dist)
        ln1.set_data(xs, speed)
        ln2.set_data(xs, angle)
        lock_time_scales(axes)
        ages = [(x + WINDOW_S) / WINDOW_S for x in xs]
        apply_ppi(ppi_sc, ppi_hd, ppi_spoke, angle, dist, ages)
        if received:
            title.set_text(f"live    {port} @ {baud}    {received} samples")
        return ln0, ln1, ln2, title

    closed = {"done": False}

    def on_close(_event):
        if closed["done"]:
            return
        closed["done"] = True
        stop.set()
        try:
            ser.close()
        except Exception:
            pass
        plt.close(fig)

    fig.canvas.mpl_connect("close_event", on_close)
    # One polar redraw is the expensive part. 5 Hz leaves the window responsive.
    anim_kwargs = dict(interval=200, blit=False)
    try:
        anim = FuncAnimation(fig, update, cache_frame_data=False, **anim_kwargs)
    except TypeError:
        anim = FuncAnimation(fig, update, **anim_kwargs)
    fig._live_anim = anim
    print(
        f"Live plot open on {port} @ {baud}. "
        "Time window: left edge is t-5 s, right edge is now. "
        "PPI: front ±90° only, radar at the center. Close the window to stop."
    )
    plt.show()
    stop.set()
    try:
        ser.close()
    except Exception:
        pass
    thread.join(timeout=1.0)


def main():
    ap = argparse.ArgumentParser(
        description="Live 5-second radar plot and front-half PPI in one window"
    )
    ap.add_argument("--port", default=None, help="Serial COM port, e.g. COM5. Default: USB-UART if present")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--file", default=None, help="Replay a captured ASCII log instead of live UART")
    args = ap.parse_args()
    if args.file:
        replay_file(args.file)
    else:
        live_plot(choose_port(args.port), args.baud)


if __name__ == "__main__":
    main()
