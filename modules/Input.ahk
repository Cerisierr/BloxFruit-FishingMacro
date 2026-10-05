; ============================================================================
;  INPUT
; ============================================================================
class Mouse {
    static down := false
    static asserted := 0.0
    static trace := false                               ; log every menu click (used during anchor / quest visits)

    ; Drive the left button to `state`; re-assert every 150 ms so a dropped
    ; SendInput event can never leave the reel zone jammed against a wall.
    static Hold(state) {
        t := Now()
        if (state != this.down || t - this.asserted >= 0.15) {
            Click(state ? "Down" : "Up")
            this.down := state
            this.asserted := t
        }
    }

    static Tap(holdSec := 0.08) {
        Click("Down")
        this.down := true
        Sleep(Round(holdSec * 1000))
        Click("Up")
        this.down := false
        this.asserted := Now()
    }

    ; Real injected movement so Roblox's GUI cursor follows (used for menus).
    static ClickAt(x, y, settle := 0.15, holdSec := 0.06) {
        if this.trace
            LogMsg("[click] menu click at " . x . "," . y)
        MouseMove(x - 4, y - 4, 0)
        Sleep(30)
        MouseMove(4, 4, 0, "R")
        Sleep(50)
        MouseMove(1, 0, 0, "R")
        MouseMove(-1, 0, 0, "R")
        Sleep(Round(settle * 1000))
        this.Tap(holdSec)
    }
}

class Keys {
    static SC_W := 0x11
    static SC_S := 0x1F
    static SC_LSHIFT := 0x2A
    static SKILLS := Map("Z", 0x2C, "X", 0x2D, "C", 0x2E, "V", 0x2F, "F", 0x21)   ; fishing-rod skill keys
    static DIGITS := Map("1", 0x02, "2", 0x03, "3", 0x04, "4", 0x05, "5", 0x06
                       , "6", 0x07, "7", 0x08, "8", 0x09, "9", 0x0A, "0", 0x0B)

    ; Scan-code tap: Roblox reads scan codes, not virtual keys.
    static Tap(sc, holdSec := 0.06) {
        code := Format("sc{:03X}", sc)
        Send("{" . code . " down}")
        Sleep(Round(holdSec * 1000))
        Send("{" . code . " up}")
    }

    static Digit(slot) {
        s := Trim(String(slot))
        return this.DIGITS.Has(s) ? this.DIGITS[s] : this.DIGITS["1"]
    }
}

; ============================================================================
;  SCREEN CAPTURE  (GDI BitBlt -> top-down 32-bit DIB, read with NumGet)
; ============================================================================
class ScreenGrab {
    static cache := Map()

    static Get(w, h) {
        key := w "x" h
        if !this.cache.Has(key) {
            if (this.cache.Count > 12)
                this.cache := Map()
            this.cache[key] := ScreenGrab(w, h)
        }
        return this.cache[key]
    }

    static Clear() {
        this.cache := Map()
    }

    __New(w, h) {
        this.w := Max(1, w)
        this.h := Max(1, h)
        this.hdcScreen := DllCall("GetDC", "ptr", 0, "ptr")
        this.hdcMem := DllCall("CreateCompatibleDC", "ptr", this.hdcScreen, "ptr")
        bi := Buffer(40, 0)
        NumPut("UInt", 40, bi, 0)
        NumPut("Int", this.w, bi, 4)
        NumPut("Int", -this.h, bi, 8)          ; negative = top-down
        NumPut("UShort", 1, bi, 12)
        NumPut("UShort", 32, bi, 14)
        bitsPtr := 0
        this.hBmp := DllCall("CreateDIBSection", "ptr", this.hdcScreen, "ptr", bi
            , "uint", 0, "ptr*", &bitsPtr, "ptr", 0, "uint", 0, "ptr")
        this.bits := bitsPtr
        this.hOld := DllCall("SelectObject", "ptr", this.hdcMem, "ptr", this.hBmp, "ptr")
    }

    ; Copy the screen rectangle whose top-left is (x, y) into the DIB.
    Capture(x, y) {
        return DllCall("BitBlt", "ptr", this.hdcMem, "int", 0, "int", 0
            , "int", this.w, "int", this.h, "ptr", this.hdcScreen
            , "int", x, "int", y, "uint", Rdp.on ? 0x00CC0020 : 0x40CC0020)   ; SRCCOPY | CAPTUREBLT (RDP: no CAPTUREBLT, it makes the cursor flicker)
    }

    __Delete() {
        try {
            DllCall("SelectObject", "ptr", this.hdcMem, "ptr", this.hOld)
            DllCall("DeleteObject", "ptr", this.hBmp)
            DllCall("DeleteDC", "ptr", this.hdcMem)
            DllCall("ReleaseDC", "ptr", 0, "ptr", this.hdcScreen)
        }
    }
}

; ============================================================================
;  REEL CONTROLLER  (time-optimal bang-bang, identical law to controller.py)
; ============================================================================
class VelEst {
    __New(win := 5) {
        this.win := win
        this.t := []
        this.x := []
    }

    Reset() {
        this.t := []
        this.x := []
    }

    Push(tv, xv) {
        ; A large jump means the target teleported: restart the fit.
        if (this.x.Length && Abs(xv - this.x[this.x.Length]) > 0.25)
            this.Reset()
        this.t.Push(tv)
        this.x.Push(xv)
        if (this.t.Length > this.win) {
            this.t.RemoveAt(1)
            this.x.RemoveAt(1)
        }
    }

    ; Least-squares slope over the sliding window.
    Value() {
        n := this.t.Length
        if (n < 3)
            return 0.0
        t0 := this.t[1]
        tm := 0.0, xm := 0.0
        Loop n {
            tm += this.t[A_Index] - t0
            xm += this.x[A_Index]
        }
        tm /= n
        xm /= n
        num := 0.0, den := 0.0
        Loop n {
            dt := (this.t[A_Index] - t0) - tm
            num += dt * (this.x[A_Index] - xm)
            den += dt * dt
        }
        return den < 1e-12 ? 0.0 : num / den
    }
}

class ReelController {
    __New() {
        this.accel0 := 1.92          ; track widths / s^2
        this.vmax := 0.545           ; track widths / s
        this.win := 5
        this.lat := 0.045            ; capture + input latency (s)
        this.deadband := 0.004
        this.edge := 0.01
        this.vz := VelEst(5)
        this.vf := VelEst(5)
        this.Reset()
    }

    Reset() {
        this.vz.Reset()
        this.vf.Reset()
        this.accel := this.accel0
        this.obs := []
        this.haveLast := false
        this.lastT := 0.0
        this.lastVz := 0.0
        this.lastHold := false
        this.pwm := false
    }

    Retarget() {
        this.vf.Reset()
    }

    ; Learn the rod's real acceleration: median of recent |dv/dt| samples.
    Adapt(tv, vzv) {
        if !this.haveLast {
            this.lastT := tv
            this.lastVz := vzv
            this.haveLast := true
            return
        }
        dt := tv - this.lastT
        if (dt > 0.004 && dt < 0.08) {
            observed := (vzv - this.lastVz) / dt
            expected := this.lastHold ? 1 : -1
            sgn := observed > 0 ? 1 : (observed < 0 ? -1 : 0)
            if (sgn == expected && Abs(vzv) < this.vmax * 0.85) {
                mag := Abs(observed)
                if (mag > 0.2 && mag < 12.0) {
                    this.obs.Push(mag)
                    if (this.obs.Length > this.win * 3)
                        this.obs.RemoveAt(1)
                    if (this.obs.Length >= this.win)
                        this.accel := Median(this.obs)
                }
            }
        }
        this.lastT := tv
        this.lastVz := vzv
    }

    ; One decision. Positions are in track widths (0..1).
    Step(tv, zoneC, fishC, zoneHalf) {
        this.vz.Push(tv, zoneC)
        this.vf.Push(tv, fishC)
        vzv := this.vz.Value()
        vfv := this.vf.Value()
        this.Adapt(tv, vzv)

        a := Max(0.2, this.accel)
        lat := this.lat
        acc := this.lastHold ? a : -a
        zPred := zoneC + vzv * lat + 0.5 * acc * lat * lat
        vzPred := Min(Max(vzv + acc * lat, -this.vmax), this.vmax)
        fPred := fishC + vfv * lat

        lo := zoneHalf + this.edge
        hi := 1.0 - zoneHalf - this.edge
        target := Min(Max(fPred, lo), hi)

        e := target - zPred
        ev := vfv - vzPred
        s := e + 0.5 * ev * Abs(ev) / a

        if (Abs(s) < this.deadband) {
            ; Alternate every tick: mean acceleration ~ 0, the zone coasts.
            this.pwm := !this.pwm
            hold := this.pwm
        } else {
            hold := (s > 0)
        }
        if (hold && vzPred >= this.vmax)
            hold := (s > this.deadband)
        else if (!hold && vzPred <= -this.vmax)
            hold := (s > -this.deadband)

        this.lastHold := hold
        return {hold: hold, err: e, vz: vzv, vf: vfv}
    }
}
