import re
import time
import urllib.request
from datetime import date, datetime, timezone

import numpy as np
from scipy import signal as dsp_signal

from stereofool.constants import BITRATE, G_POLY, OFFSETS, RDS_FREQ
from stereofool.state import monitor_data, monitor_lock, rds_state, resolved_cache

EBU_LATIN_MAP = {
    "é": "e",
    "è": "e",
    "ê": "e",
    "ë": "e",
    "á": "a",
    "à": "a",
    "â": "a",
    "ä": "a",
    "å": "a",
    "í": "i",
    "ì": "i",
    "î": "i",
    "ï": "i",
    "ó": "o",
    "ò": "o",
    "ô": "o",
    "ö": "o",
    "ú": "u",
    "ù": "u",
    "û": "u",
    "ü": "u",
    "ç": "c",
    "ñ": "n",
    "ß": "ss",
    "€": "E",
    "æ": "ae",
    "œ": "oe",
    "°": " ",
    "™": " ",
    "®": " ",
}


def convert_to_ebu_latin(text):
    result = []
    for char in text:
        if ord(char) > 127:
            result.append(EBU_LATIN_MAP.get(char, "?"))
        else:
            result.append(char)
    return "".join(result)


def parse_text_source(text):
    if not text:
        return ""
    try:
        if "\\" in text:
            failed = False

            def file_repl(m):
                nonlocal failed
                try:
                    with open(m.group(1), "r", encoding="utf-8-sig") as f:
                        content = f.read().strip()
                        return convert_to_ebu_latin(content)
                except Exception:
                    failed = True
                    return ""

            def url_repl(m):
                nonlocal failed
                try:
                    with urllib.request.urlopen(m.group(1), timeout=2) as r:
                        content = r.read().decode("utf-8").strip()
                        return convert_to_ebu_latin(content)
                except Exception:
                    failed = True
                    return ""

            def clean_spaces(s):
                return s.replace("\r", " ").replace("\n", " ")

            t = re.sub(r"\\R\"([^\"]+)\"", lambda m: clean_spaces(file_repl(m)).upper(), text)
            t = re.sub(r"\\r\"([^\"]+)\"", lambda m: clean_spaces(file_repl(m)), t)
            t = re.sub(r"\\w\"([^\"]+)\"", lambda m: clean_spaces(url_repl(m)), t)
            if failed:
                return None
            return t
        return text
    except Exception:
        return text


class RTPlusParser:
    @staticmethod
    def parse(text, fmt_str, centered=False, limit=64):
        tags = []
        if not text or not fmt_str:
            return tags
        offset = 0
        if centered and len(text) < limit:
            offset = (limit - len(text)) // 2
        pattern = re.escape(fmt_str)
        pattern = pattern.replace(r"\{artist\}", r"(?P<artist>.+)")
        pattern = pattern.replace(r"\{title\}", r"(?P<title>.+)")
        match = re.search(pattern, text)
        if match:
            for name in match.groupdict():
                raw_start = match.start(name)
                length = len(match.group(name))
                real_start = raw_start + offset
                c_type = 1 if name == "title" else 4
                if real_start < 64 and length > 0:
                    if real_start + length > 64:
                        length = 64 - real_start
                    tags.append((c_type, real_start, length))
        return tags


class RDSHelper:
    @staticmethod
    def crc(data, offset):
        reg = int(data) << 10
        for _ in range(16):
            if (reg >> 25) & 1:
                reg ^= G_POLY << 15
            reg = (reg << 1) & 0x3FFFFFF
        return ((reg >> 16) & 0x3FF) ^ offset

    @staticmethod
    def get_group_bits(g_type, ver, b2_tail, b3_val, b4_val):
        try:
            pi_v = int(rds_state["pi"], 16)
        except Exception:
            pi_v = 0x0000
        b1 = (pi_v << 10) | RDSHelper.crc(pi_v, OFFSETS["A"])
        b2_v = (
            (int(g_type) << 12)
            | (int(ver) << 11)
            | (int(rds_state["tp"]) << 10)
            | (int(rds_state["pty"]) << 5)
            | (int(b2_tail) & 0x1F)
        )
        b2 = (b2_v << 10) | RDSHelper.crc(b2_v, OFFSETS["B"])
        b3 = (int(b3_val) << 10) | RDSHelper.crc(b3_val, OFFSETS["Cp"] if ver else OFFSETS["C"])
        b4 = (int(b4_val) << 10) | RDSHelper.crc(b4_val, OFFSETS["D"])
        bits = []
        for b in [b1, b2, b3, b4]:
            for i in range(25, -1, -1):
                bits.append((b >> i) & 1)
        return bits


class RDSScheduler:
    def __init__(self):
        self.ps_ptr, self.rt_ptr, self.ptyn_ptr, self.lps_ptr, self.af_ptr = 0, 0, 0, 0, 0
        self.start_time = time.time()
        self.ct_min_lock = -1
        self.last_rt_content = ""
        self.last_rt_text_content = ""
        self.rt_ab_flag = 0
        self.rt_ab_cycles = 0
        self.last_rt_buf = 0
        self.rt_sequence, self.rt_seq_idx = [], 0
        self.rt_seq_start_time = 0
        self.last_ps_content = ""
        self.ps_sequence, self.ps_seq_idx = [], 0
        self.ps_seq_start_time = 0
        self.burst_counter = 0
        self.last_lps_content = ""
        self.lps_sequence, self.lps_seq_idx = [], 0
        self.lps_seq_start_time = 0
        self.last_ptyn_content = ""
        self.ptyn_sequence, self.ptyn_seq_idx = [], 0
        self.ptyn_seq_start_time = 0
        self.schedule_ptr = 0
        self.rt_plus_toggle = 0
        self.rt_plus_tags = []
        self.last_rt_clean = ""
        self.schedule_gen_counter = 0

    def get_text(self, key) -> str:
        val = rds_state.get(key, "")
        text = "" if val is None else str(val)
        return resolved_cache.get(key, text) if "\\" in text else text

    def freq_code(self, f):
        try:
            return round((float(f) - 87.5) / 0.1) if 87.6 <= float(f) <= 107.9 else 205
        except Exception:
            return 205

    def split(self, text, width=8, center=False):
        def pad(value: str) -> str:
            return value.center(width) if center else value.ljust(width)

        if width <= 8:
            if text is None:
                return [pad("")]
            if len(text) <= width:
                return [pad(text)]
            words, frames, curr = text.split(), [], ""
            for w in words:
                if len(w) > width:
                    if curr:
                        frames.append(pad(curr))
                        curr = ""
                    chunks = [w[i : i + width] for i in range(0, len(w), width)]
                    for c in chunks[:-1]:
                        frames.append(pad(c))
                    curr = chunks[-1]
                else:
                    test = (curr + " " + w).strip() if curr else w
                    if len(test) <= width:
                        curr = test
                    else:
                        frames.append(pad(curr))
                        curr = w
            if curr:
                frames.append(pad(curr))
            return frames
        words, frames, curr = text.split(), [], ""
        for w in words:
            if len(w) > width:
                if curr:
                    frames.append(pad(curr))
                    curr = ""
                chunks = [w[i : i + width] for i in range(0, len(w), width)]
                for c in chunks[:-1]:
                    frames.append(pad(c))
                curr = chunks[-1]
            else:
                test = (curr + " " + w).strip() if curr else w
                if len(test) <= width:
                    curr = test
                else:
                    frames.append(pad(curr))
                    curr = w
        if curr:
            frames.append(pad(curr))
        return frames

    def parse_smart(self, raw, width, center):
        seq = []
        if re.match(r"\s*\d+s:", raw):
            parts = re.split(r"\s*/\s*", raw)
            if len(parts) > 1:
                for p in parts:
                    m = re.match(r"\s*(\d+)s:(.*)", p)
                    if m:
                        for sf in self.split(m.group(2), width, center):
                            seq.append((int(m.group(1)), sf))
                    else:
                        for sf in self.split(p.strip(), width, center):
                            seq.append((2.5, sf))
            else:
                timed = list(re.finditer(r"(\d+)s:(.*?)(?=(?:\s+\d+s:)|$)", raw))
                if timed:
                    for m in timed:
                        for sf in self.split(m.group(2).strip(), width, center):
                            seq.append((int(m.group(1)), sf))
        else:
            if width <= 8:
                if raw == "" or raw is None:
                    return [(10, " " * width)]
                if len(raw) <= width:
                    return [(10, self.split(raw, width, center)[0])]
                for sf in self.split(raw, width, center):
                    seq.append((2.5, sf))
            else:
                if not raw.strip():
                    return [(10, " " * width)]
                if len(raw.strip()) <= width:
                    return [(10, self.split(raw, width, center)[0])]
                for sf in self.split(raw.strip(), width, center):
                    seq.append((2.5, sf))
        return seq

    def parse_schedule_string(self, seq_str):
        out = []
        tokens = seq_str.upper().replace(",", " ").split()
        for t in tokens:
            match = re.match(r"(\d+)([AB]?)", t)
            if match:
                grp = int(match.group(1))
                ver = 1 if match.group(2) == "B" else 0
                out.append((grp, ver))
        return out if out else [(0, 0)]

    def generate_auto_schedule(self):
        seq = [
            (0, 0),
            (0, 0),
            (2, 0),
            (0, 0),
            (2, 0),
            (0, 0),
            (0, 0),
            (0, 0),
            (2, 0),
            (0, 0),
            (2, 0),
            (0, 0),
            (2, 0),
            (0, 0),
            (2, 0),
            (0, 0),
            (2, 0),
            (0, 0),
            (2, 0),
            (0, 0),
        ]
        if rds_state["en_lps"]:
            seq.append((15, 0))
            seq.append((15, 0))
        if rds_state["en_ptyn"]:
            seq.append((10, 0))
            seq.append((10, 0))
        if rds_state["en_id"]:
            seq.append((1, 0))
        if rds_state["en_rt_plus"]:
            if self.schedule_gen_counter % 2 == 0:
                seq.append((3, 0))
            seq.append((11, 0))
        self.schedule_gen_counter += 1
        return seq

    def generate_standard_schedule(self):
        g2_ver = 1 if str(rds_state.get("rt_mode", "2A")).upper() == "2B" else 0
        seq = [
            (0, 0),
            (0, 0),
            (0, 0),
            (2, g2_ver),
            (0, 0),
            (2, g2_ver),
            (0, 0),
            (0, 0),
            (0, 0),
            (2, g2_ver),
            (0, 0),
            (2, g2_ver),
            (0, 0),
            (0, 0),
        ]
        if rds_state["en_id"]:
            seq.append((1, 0))
        if rds_state["en_ptyn"]:
            seq.append((10, 0))
        if rds_state["en_rt_plus"]:
            seq.append((3, 0))
            seq.append((11, 0))
        if rds_state.get("scheduler_standard_lps") and rds_state["en_lps"]:
            seq.append((15, 0))
        return seq

    def next(self):
        now = datetime.now(timezone.utc)
        if rds_state["en_ct"] and now.second == 0 and now.minute != self.ct_min_lock:
            self.ct_min_lock = now.minute
            mjd = (date.today() - date(1858, 11, 17)).days
            b4 = (
                ((now.hour & 0x0F) << 12)
                | (now.minute << 6)
                | ((1 if rds_state["tz_offset"] < 0 else 0) << 5)
                | int(abs(rds_state["tz_offset"]) * 2)
            )
            return RDSHelper.get_group_bits(
                4, 0, (mjd >> 15) & 3, ((mjd & 0x7FFF) << 1) | ((now.hour >> 4) & 1), b4
            )

        if rds_state.get("scheduler_standard"):
            schedule = self.generate_standard_schedule()
        else:
            schedule = (
                self.generate_auto_schedule()
                if rds_state["scheduler_auto"]
                else self.parse_schedule_string(rds_state["group_sequence"])
            )

        if self.burst_counter > 0:
            g_type, g_ver = 0, 0
            self.burst_counter -= 1
        else:
            g_type, g_ver = schedule[self.schedule_ptr % len(schedule)]
            self.schedule_ptr += 1

        if g_type == 0:
            raw = self.get_text("ps_dynamic")
            sig = f"{raw}_{rds_state['ps_centered']}"
            if sig != self.last_ps_content:
                self.last_ps_content, self.ps_ptr = sig, 0
                if rds_state["scheduler_auto"]:
                    self.burst_counter = 16
                self.ps_sequence = self.parse_smart(raw, 8, rds_state["ps_centered"])
                self.ps_seq_idx, self.ps_seq_start_time = 0, time.time()
            if not self.ps_sequence:
                self.ps_sequence = [(10, "RDS_PRO ")]
            dur, txt = self.ps_sequence[self.ps_seq_idx % len(self.ps_sequence)]
            txt = (txt or "").ljust(8)[:8]
            with monitor_lock:
                monitor_data["ps"] = txt
            if (time.time() - self.ps_seq_start_time) >= dur:
                self.ps_seq_idx += 1
                self.ps_seq_start_time, self.ps_ptr = time.time(), 0
                dur, txt = self.ps_sequence[self.ps_seq_idx % len(self.ps_sequence)]
                if (
                    rds_state["scheduler_auto"]
                    and self.ps_sequence[self.ps_seq_idx % len(self.ps_sequence)][1] != txt
                ):
                    self.burst_counter = 12
            seg = self.ps_ptr % 4
            self.ps_ptr += 1
            tail = (
                (rds_state["ta"] << 4)
                | (rds_state["ms"] << 3)
                | (
                    [
                        rds_state["di_dyn"],
                        rds_state["di_comp"],
                        rds_state["di_head"],
                        rds_state["di_stereo"],
                    ][seg]
                    << 2
                )
                | seg
            )
            b3 = 0xE0E0
            if rds_state["en_af"] and g_ver == 0:
                afs = [x.strip() for x in rds_state["af_list"].split(",") if x.strip()]
                if afs:
                    if self.af_ptr == 0:
                        b3, self.af_ptr = (224 + len(afs)) << 8 | self.freq_code(afs[0]), 1
                    else:
                        f1 = self.freq_code(afs[self.af_ptr])
                        f2 = (
                            self.freq_code(afs[self.af_ptr + 1])
                            if self.af_ptr + 1 < len(afs)
                            else 205
                        )
                        b3, self.af_ptr = (
                            (f1 << 8) | f2,
                            (self.af_ptr + 2) if self.af_ptr + 2 < len(afs) else 0,
                        )
            if g_ver == 1:
                b3 = int(rds_state["pi"], 16)
            return RDSHelper.get_group_bits(
                0, g_ver, tail, b3, (ord(txt[seg * 2]) << 8) | ord(txt[seg * 2 + 1])
            )

        if g_type == 2:
            if rds_state["rt_manual_buffers"]:
                buf = (
                    int((time.time() - self.start_time) / rds_state["rt_cycle_time"]) % 2
                    if rds_state["rt_cycle"]
                    else rds_state["rt_active_buffer"]
                )
                raw = self.get_text("rt_a" if buf == 0 else "rt_b")
            else:
                raw_input = self.get_text("rt_text")
                limit = 32 if rds_state["rt_mode"] == "2B" else 64
                if not self.rt_sequence or raw_input != self.last_rt_text_content:
                    if "/" in raw_input:
                        self.rt_sequence = self.parse_smart(raw_input, limit, False)
                    else:
                        m = re.match(r"\s*(\d+)s:(.*)", raw_input.strip())
                        if m:
                            duration = int(m.group(1))
                            text = m.group(2).strip()[:limit]
                        else:
                            duration = 10
                            text = raw_input.strip()[:limit]
                        self.rt_sequence = [(duration, text)]
                    self.rt_seq_idx = 0
                    self.rt_seq_start_time = time.time()
                    self.last_rt_text_content = raw_input
                    self.rt_ab_flag = 1 - self.rt_ab_flag
                    self.rt_ab_cycles = 0
                    self.rt_ptr = 0
                dur, txt = self.rt_sequence[self.rt_seq_idx % len(self.rt_sequence)]
                if len(self.rt_sequence) > 1 and time.time() - self.rt_seq_start_time >= dur:
                    self.rt_seq_idx += 1
                    self.rt_seq_start_time = time.time()
                    dur, txt = self.rt_sequence[self.rt_seq_idx % len(self.rt_sequence)]
                    if not rds_state["rt_cycle_ab"]:
                        self.rt_ab_flag = 1 - self.rt_ab_flag
                buf = self.rt_ab_flag
                raw = txt.strip()
            if buf != self.last_rt_buf:
                self.rt_ptr = 0
                self.last_rt_buf = buf
            sig = f"{raw}_{rds_state['rt_centered']}_{rds_state['rt_cr']}"
            limit = 32 if rds_state["rt_mode"] == "2B" else 64
            if raw != self.last_rt_clean:
                self.last_rt_clean = raw
                self.rt_plus_toggle = 1 - self.rt_plus_toggle
                fmt = rds_state["rt_plus_format_a"] if buf == 0 else rds_state["rt_plus_format_b"]
                self.rt_plus_tags = RTPlusParser.parse(
                    raw, fmt, centered=rds_state["rt_centered"], limit=limit
                )
                tag_str = []
                display_clean = (
                    (raw + "\r")
                    if rds_state["rt_cr"]
                    else raw.center(limit)
                    if rds_state["rt_centered"]
                    else raw.ljust(limit)
                )
                for t in self.rt_plus_tags:
                    t_name = "Title" if t[0] == 1 else "Artist"
                    content = display_clean[t[1] : t[1] + t[2]]
                    tag_str.append(f"{t_name}: {content}")
                with monitor_lock:
                    monitor_data["rt_plus_info"] = " | ".join(tag_str)
            if sig != self.last_rt_content:
                self.rt_ptr, self.last_rt_content = 0, sig
            clean = (
                (raw + "\r")
                if rds_state["rt_cr"]
                else raw.center(limit)
                if rds_state["rt_centered"]
                else raw.ljust(limit)
            )
            with monitor_lock:
                monitor_data["rt"] = clean
            v = g_ver
            bpg = 2 if v == 1 else 4
            if self.rt_ptr * bpg >= len(clean) or (
                clean.find("\r") != -1 and self.rt_ptr * bpg > clean.find("\r")
            ):
                if rds_state.get("rt_cycle_ab"):
                    self.rt_ab_cycles += 1
                    try:
                        cycle_target = int(rds_state.get("rt_ab_cycle_count", 2))
                    except Exception:
                        cycle_target = 2
                    if cycle_target < 1:
                        cycle_target = 1
                    if self.rt_ab_cycles >= cycle_target:
                        self.rt_ab_flag = 1 - self.rt_ab_flag
                        self.rt_ab_cycles = 0
                self.rt_ptr = 0
            pad = clean.ljust(64)
            a = self.rt_ptr % 16
            self.rt_ptr += 1
            b3_val = (ord(pad[a * 4]) << 8) | ord(pad[a * 4 + 1]) if v == 0 else 0
            b4_val = (
                (ord(pad[a * 4 + 2]) << 8) | ord(pad[a * 4 + 3])
                if v == 0
                else (ord(pad[a * 2]) << 8) | ord(pad[a * 2 + 1])
            )
            return RDSHelper.get_group_bits(2, v, (buf << 4) | a, b3_val, b4_val)

        if g_type == 3 and rds_state["en_rt_plus"]:
            return RDSHelper.get_group_bits(3, 0, 22, 0x0000, 0x4BD7)

        if g_type == 11 and rds_state["en_rt_plus"]:
            t1_typ, t1_start, t1_len = 0, 0, 0
            t2_typ, t2_start, t2_len = 0, 0, 0
            tags_to_send = self.rt_plus_tags[:2]
            if len(tags_to_send) == 2:
                if tags_to_send[1][2] > 31 and tags_to_send[0][2] <= 31:
                    tags_to_send.reverse()
            if len(tags_to_send) > 0:
                t1_typ, t1_start, t1_len = tags_to_send[0]
                if t1_len > 0:
                    t1_len -= 1
            if len(tags_to_send) > 1:
                t2_typ, t2_start, t2_len = tags_to_send[1]
                if t2_len > 0:
                    t2_len -= 1
            b2_tail = ((self.rt_plus_toggle & 1) << 4) | 0x08 | ((t1_typ >> 3) & 0x07)
            b3_val = (
                ((t1_typ & 0x07) << 13)
                | ((t1_start & 0x3F) << 7)
                | ((t1_len & 0x3F) << 1)
                | ((t2_typ >> 5) & 0x01)
            )
            b4_val = ((t2_typ & 0x1F) << 11) | ((t2_start & 0x3F) << 5) | (t2_len & 0x1F)
            return RDSHelper.get_group_bits(11, 0, b2_tail, b3_val, b4_val)

        if g_type == 15 and rds_state["en_lps"]:
            raw = self.get_text("ps_long_32")
            if raw != self.last_lps_content:
                self.last_lps_content, self.lps_ptr = raw, 0
            if not self.lps_sequence or raw != self.lps_sequence[0][1].strip():
                self.lps_sequence = self.parse_smart(raw, 32, rds_state["lps_centered"])
            dur, txt = self.lps_sequence[self.lps_seq_idx % len(self.lps_sequence)]
            with monitor_lock:
                monitor_data["lps"] = txt + ("\r" if rds_state["lps_cr"] else "")
            if (time.time() - self.lps_seq_start_time) >= dur:
                self.lps_seq_idx += 1
                self.lps_seq_start_time, self.lps_ptr = time.time(), 0
                dur, txt = self.lps_sequence[self.lps_seq_idx % len(self.lps_sequence)]
            if rds_state["lps_cr"]:
                txt_stripped = txt.rstrip()
                lps_txt = (txt_stripped + "\r").encode("utf-8")
                if len(lps_txt) < 4:
                    lps_txt = lps_txt.ljust(4, b"\x00")
            else:
                lps_txt = txt.encode("utf-8").ljust(32)[:32]
            seg = self.lps_ptr % 8
            self.lps_ptr += 1
            if rds_state["lps_cr"] and (seg * 4) >= len(lps_txt):
                self.schedule_ptr += 1
                return self.next()
            while len(lps_txt) < (seg + 1) * 4:
                lps_txt += b"\x00"
            return RDSHelper.get_group_bits(
                15,
                g_ver,
                seg,
                (lps_txt[seg * 4] << 8) | lps_txt[seg * 4 + 1],
                (lps_txt[seg * 4 + 2] << 8) | lps_txt[seg * 4 + 3],
            )

        if g_type == 10 and rds_state["en_ptyn"]:
            raw = self.get_text("ptyn")
            if raw != self.last_ptyn_content:
                self.last_ptyn_content, self.ptyn_ptr = raw, 0
            if not self.ptyn_sequence or raw != self.ptyn_sequence[0][1].strip():
                self.ptyn_sequence = self.parse_smart(raw, 8, rds_state["ptyn_centered"])
            dur, txt = self.ptyn_sequence[self.ptyn_seq_idx % len(self.ptyn_sequence)]
            with monitor_lock:
                monitor_data["ptyn"] = txt
            if (time.time() - self.ptyn_seq_start_time) >= dur:
                self.ptyn_seq_idx += 1
                self.ptyn_seq_start_time, self.ptyn_ptr = time.time(), 0
                dur, txt = self.ptyn_sequence[self.ptyn_seq_idx % len(self.ptyn_sequence)]
            txt = txt.ljust(8)
            seg = self.ptyn_ptr % 2
            self.ptyn_ptr += 1
            return RDSHelper.get_group_bits(
                10,
                g_ver,
                seg,
                (ord(txt[seg * 4]) << 8) | ord(txt[seg * 4 + 1]),
                (ord(txt[seg * 4 + 2]) << 8) | ord(txt[seg * 4 + 3]),
            )

        if g_type == 1 and rds_state["en_id"]:
            vars = [0, 3]
            vnt = vars[int(time.time() / 2) % 2]
            return RDSHelper.get_group_bits(
                1,
                g_ver,
                0,
                (vnt << 12) | (int(rds_state["ecc" if vnt == 0 else "lic"], 16) & 0xFF),
                0,
            )

        return RDSHelper.get_group_bits(0, 0, 0, 0xE0E0, 0xE0E0)


class RDSSubcarrier:
    def __init__(self, sample_rate):
        self.sample_rate = sample_rate
        self.sched = RDSScheduler()
        self.bit_phase = 0.0
        self.last_bit = 0
        self.bit_queue = []
        self.taps = self._biphase_shaping_taps(self.sample_rate, BITRATE)
        self.zi = np.zeros(len(self.taps) - 1)
        self.gaussian_enabled = bool(rds_state.get("rds_gaussian_enabled", True))
        self.gaussian_bw_hz = float(rds_state.get("rds_gaussian_bw_hz", 2400.0))
        self.gaussian_taps_len = int(rds_state.get("rds_gaussian_taps", 81))
        self.gaussian_taps = self._gaussian_taps(
            self.sample_rate, self.gaussian_bw_hz, self.gaussian_taps_len
        )
        self.gaussian_zi = np.zeros(len(self.gaussian_taps) - 1)
        self.shaping_peak = self._calc_shape_peak()

    @staticmethod
    def _biphase_shaping_taps(sample_rate, bitrate, num_taps=301):
        td = 1.0 / bitrate
        fmax = min(sample_rate / 2.0, 2.0 * bitrate)
        if fmax <= 0:
            fmax = 1.0
        points = 128
        freqs = np.linspace(0.0, fmax, points)
        gains = np.cos(np.pi * freqs * td / 4.0)
        freqs = np.concatenate([freqs, [sample_rate / 2.0]])
        gains = np.concatenate([gains, [0.0]])
        taps = dsp_signal.firwin2(num_taps, freqs, gains, fs=sample_rate)
        taps = np.asarray(taps, dtype=np.float64)
        energy = float(np.sqrt(np.sum(taps**2)))
        if energy > 0:
            taps /= energy
        return taps

    @staticmethod
    def _gaussian_taps(sample_rate, bandwidth_hz, num_taps=81):
        num_taps = max(9, int(num_taps) | 1)
        bandwidth_hz = max(100.0, float(bandwidth_hz))
        sigma = sample_rate / (2.0 * np.pi * bandwidth_hz)
        half = num_taps // 2
        idx = np.arange(num_taps) - half
        taps = np.exp(-0.5 * (idx / sigma) ** 2)
        taps = taps.astype(np.float64)
        taps /= float(np.sum(taps)) if np.sum(taps) else 1.0
        return taps

    def _refresh_gaussian(self):
        enabled = bool(rds_state.get("rds_gaussian_enabled", True))
        bw = float(rds_state.get("rds_gaussian_bw_hz", 2400.0))
        taps_len = int(rds_state.get("rds_gaussian_taps", 81))
        if (
            enabled == self.gaussian_enabled
            and abs(bw - self.gaussian_bw_hz) < 1.0
            and taps_len == self.gaussian_taps_len
        ):
            return
        self.gaussian_enabled = enabled
        self.gaussian_bw_hz = bw
        self.gaussian_taps_len = taps_len
        self.gaussian_taps = self._gaussian_taps(self.sample_rate, bw, taps_len)
        self.gaussian_zi = np.zeros(len(self.gaussian_taps) - 1)
        self.shaping_peak = self._calc_shape_peak()

    def _calc_shape_peak(self):
        frames = 8192
        bit_phase = 0.0
        last_bit = 0
        bb = np.zeros(frames, dtype=np.float64)
        for i in range(frames):
            prev_phase = bit_phase
            bit_phase += BITRATE / self.sample_rate
            if bit_phase >= 1.0:
                bit_phase -= 1.0
                last_bit ^= 1
                bb[i] += 1.0 if last_bit else -1.0
            if prev_phase < 0.5 <= bit_phase:
                bb[i] += -1.0 if last_bit else 1.0
        shaped = np.asarray(dsp_signal.lfilter(self.taps, 1.0, bb))
        if self.gaussian_enabled and len(self.gaussian_taps) > 1:
            shaped = np.asarray(dsp_signal.lfilter(self.gaussian_taps, 1.0, shaped))
        peak = float(np.max(np.abs(shaped))) if shaped.size else 1.0
        return max(peak, 1e-6)

    def synthesize(self, frames, phase_seconds=0.0):
        # Calibrated so rds_level (kHz) matches measured deviation at 75 kHz max.
        lvl_rds = float(rds_state["rds_level"]) / 75.0
        if lvl_rds < 0:
            lvl_rds = 0.0
        rds_freq = float(rds_state.get("rds_freq", RDS_FREQ))
        if rds_freq < 1000:
            rds_freq = 1000
        if rds_freq > 120000:
            rds_freq = 120000
        while len(self.bit_queue) < frames:
            self.bit_queue.extend(self.sched.next())
        bb = np.zeros(frames)
        for i in range(frames):
            impulse = 0.0
            prev_phase = self.bit_phase
            self.bit_phase += BITRATE / self.sample_rate
            if self.bit_phase >= 1.0:
                self.bit_phase -= 1.0
                if not self.bit_queue:
                    self.bit_queue.extend(self.sched.next())
                self.last_bit ^= self.bit_queue.pop(0)
                impulse += 1.0 if self.last_bit else -1.0
            if prev_phase < 0.5 <= self.bit_phase:
                impulse += -1.0 if self.last_bit else 1.0
            bb[i] = impulse
        shaped, self.zi = dsp_signal.lfilter(self.taps, 1.0, bb, zi=self.zi)
        self._refresh_gaussian()
        if self.gaussian_enabled and len(self.gaussian_taps) > 1:
            shaped, self.gaussian_zi = dsp_signal.lfilter(
                self.gaussian_taps, 1.0, shaped, zi=self.gaussian_zi
            )
        shaped = shaped / self.shaping_peak
        t = (np.arange(frames) / self.sample_rate) + phase_seconds
        rds_sig = shaped * np.sin(2 * np.pi * rds_freq * t) * lvl_rds
        return rds_sig
