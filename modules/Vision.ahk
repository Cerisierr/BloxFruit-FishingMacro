; ============================================================================
;  VISION - colour rules (RGB) ported from vision.py
; ============================================================================
; Dark neutral / slightly blue panel. The track is translucent, so it is darker
; over wood (33,30,29) and lighter over bright flat sea or sky (47,53,56).
IsTrackPx(r, g, b) {
    return b >= 18 && b <= 66 && r <= 70 && g <= 70 && Abs(b - g) <= 14 && Abs(g - r) <= 14
}

IsZonePx(r, g, b) {                          ; green zone, normal + alarm look
    if (Abs(b - r) > 16)
        return false
    if (g > b + 10 && g > r + 10 && g > 62)
        return true
    return Abs(g - b) <= 12 && g >= 62 && g <= 170
}

IsFishPx(r, g, b) {
    return b > 110 && b > r + 60 && g > r + 30
}

IsChestPx(r, g, b) {
    return r > 140 && g > 90 && b < 130 && r > b + 60 && g > b + 20
}

; Fraction of sampled pixels on row y (between xl..xr) that belong to the bar.
BandFrac(bits, w, y, xl, xr) {
    n := 0, hit := 0
    base := y * w * 4
    x := xl
    while (x <= xr) {
        v := NumGet(bits, base + x * 4, "UInt")
        rr := (v >> 16) & 255
        gg := (v >> 8) & 255
        bb := v & 255
        n++
        if (IsTrackPx(rr, gg, bb) || IsZonePx(rr, gg, bb) || IsFishPx(rr, gg, bb)
            || IsChestPx(rr, gg, bb))
            hit++
        x += 6
    }
    return n ? hit / n : 0.0
}

; Locate the reel bar. Identified structurally: a long two-tone green progress
; strip with the dark track band directly above it. Returns a geometry object
; or 0.
FindBar() {
    win := BotState.win
    r := SubRect(win, Regions.bar)
    if (r.w < 50 || r.h < 10)
        return 0
    gr := ScreenGrab.Get(r.w, r.h)
    gr.Capture(r.x, r.y)
    bits := gr.bits
    w := r.w, h := r.h
    minW := Floor(win.w * 0.18)
    maxW := Floor(win.w * 0.99)
    diedHud := DeathRecentlyHud()
    centerX := win.w // 2 - (r.x - win.x)

    bestW := 0, bTop := -1, bBot := -1, bL := 0, bR := 0
    gTop := -1, gBot := -1, gL := 0, gR := 0

    y := 0
    while (y < h) {
        base := y * w * 4
        runStart := -1, last := -1
        curLen := 0, curL := 0, curR := 0
        leftL := -1, leftR := -1, rightL := -1, rightR := -1
        x := 0
        while (x < w) {
            v := NumGet(bits, base + x * 4, "UInt")
            rr := (v >> 16) & 255
            gg := (v >> 8) & 255
            bb := v & 255
            if (gg > bb + 15 && gg > rr + 15 && gg > 40) {       ; progress strip
                if (runStart < 0)
                    runStart := x
                last := x
            } else if (runStart >= 0 && x - last > 6) {
                if (last - runStart > curLen) {
                    curLen := last - runStart
                    curL := runStart
                    curR := last
                }
                if diedHud {
                    if ((runStart + last) / 2 < centerX) {
                        leftL := (leftL < 0) ? runStart : Min(leftL, runStart)
                        leftR := Max(leftR, last)
                    } else {
                        rightL := (rightL < 0) ? runStart : Min(rightL, runStart)
                        rightR := Max(rightR, last)
                    }
                }
                runStart := -1
            }
            x += 2
        }
        if (runStart >= 0 && last - runStart > curLen) {
            curLen := last - runStart
            curL := runStart
            curR := last
        }
        if (diedHud && runStart >= 0) {
            if ((runStart + last) / 2 < centerX) {
                leftL := (leftL < 0) ? runStart : Min(leftL, runStart)
                leftR := Max(leftR, last)
            } else {
                rightL := (rightL < 0) ? runStart : Min(rightL, runStart)
                rightR := Max(rightR, last)
            }
        }
        ; The white death-status label can hide the center of the green strip.
        ; Stitch only the two fragments around a centered, text-sized gap.
        if (diedHud && leftL >= 0 && rightL >= 0) {
            gap := rightL - leftR
            gapCenter := (leftR + rightL) / 2
            mergedW := rightR - leftL
            if (gap > 0 && gap <= Ceil(win.w * 0.38)
                && Abs(gapCenter - centerX) <= win.w * 0.08
                && mergedW >= minW && mergedW <= maxW && mergedW > curLen) {
                curLen := mergedW
                curL := leftL
                curR := rightR
            }
        }

        if (curLen >= minW && curLen <= maxW) {
            if (gTop >= 0 && Abs(curL - gL) <= 8 && Abs(curR - gR) <= 8) {
                gBot := y
                if (curR - curL > gR - gL) {
                    gL := curL
                    gR := curR
                }
            } else {
                if (gTop >= 0 && gR - gL > bestW) {
                    bestW := gR - gL
                    bTop := gTop
                    bBot := gBot
                    bL := gL
                    bR := gR
                }
                gTop := y
                gBot := y
                gL := curL
                gR := curR
            }
        } else if (gTop >= 0) {
            if (gR - gL > bestW) {
                bestW := gR - gL
                bTop := gTop
                bBot := gBot
                bL := gL
                bR := gR
            }
            gTop := -1
        }
        y++
    }
    if (gTop >= 0 && gR - gL > bestW) {
        bestW := gR - gL
        bTop := gTop
        bBot := gBot
        bL := gL
        bR := gR
    }
    if (bTop < 0)
        return 0

    tw := bR - bL + 2
    progH := bBot - bTop + 1
    if (progH < 3 || progH > Ceil(0.05 * tw))            ; reject scenery blocks
        return 0

    ; Playfield band: rows of dark track / zone / tiles just above the strip.
    bandBotL := -1
    maxGap := Ceil(0.03 * tw)
    k := 0
    while (k <= maxGap && bTop - 1 - k >= 0) {
        if (BandFrac(bits, w, bTop - 1 - k, bL, bR) >= 0.5) {
            bandBotL := bTop - 1 - k
            break
        }
        k++
    }
    if (bandBotL < 0)
        return 0
    bandTopL := bandBotL
    while (bandTopL - 1 >= 0 && BandFrac(bits, w, bandTopL - 1, bL, bR) >= 0.4)
        bandTopL--
    bandH := bandBotL - bandTopL + 1
    if (bandTopL == 0)                                    ; clipped by the search box
        bandH := Max(bandH, Round(0.055 * tw))
    if (bandH < Max(6, Floor(0.02 * tw)))
        return 0

    x0 := r.x + bL
    progTopAbs := r.y + bTop
    progBotAbs := r.y + bBot
    bandBotAbs := r.y + bandBotL
    bandTopAbs := bandBotAbs - bandH + 1
    hh := progBotAbs - bandTopAbs + 1

    geo := {x0: x0, tw: tw, bandTop: bandTopAbs, hh: hh, bandH: bandH
          , grab: ScreenGrab.Get(tw, hh), rows: [], progRows: []}
    Loop 7
        geo.rows.Push(Round((bandH - 1) * (0.15 + 0.70 * (A_Index - 1) / 6)))
    pl0 := progTopAbs - bandTopAbs
    ph := progBotAbs - progTopAbs
    geo.progRows.Push(pl0 + Round(ph * 0.25))
    geo.progRows.Push(pl0 + Round(ph * 0.50))
    geo.progRows.Push(pl0 + Round(ph * 0.75))
    return geo
}

; The track width is measured once per catch: keep the widest of a few reads,
; because a tile over the strip can make a single read come back short.
AcquireWidest(geo) {
    best := geo
    Loop 4 {
        Sleep(20)
        g2 := FindBar()
        if (g2 && g2.tw > best.tw)
            best := g2
    }
    return best
}

; One grab -> zone / fish / chest spans (pixels, relative to the track).
; Returns 0 when the bar is not readable.
ReadBar(geo, zoneWRef, chestMinW) {
    gr := geo.grab
    gr.Capture(geo.x0, geo.bandTop)
    bits := gr.bits
    w := geo.tw
    rows := geo.rows
    nr := rows.Length
    zThr := Ceil(nr * 0.5)
    fThr := Ceil(nr * 0.25)
    cThr := Ceil(nr * 0.30)

    zl := -1, zr := -1, nz := 0
    fs := -1, fe := -1, bfLen := -1, bfS := -1, bfE := -1
    cs := -1, ce := -1, bcLen := -1, bcS := -1, bcE := -1
    trackHits := 0, total := 0

    x := 0
    while (x < w) {
        zc := 0, fc := 0, cc := 0
        for ry in rows {
            v := NumGet(bits, (ry * w + x) * 4, "UInt")
            rr := (v >> 16) & 255
            gg := (v >> 8) & 255
            bb := v & 255
            total++
            if (bb >= 18 && bb <= 66 && rr <= 70 && gg <= 70 && Abs(bb - gg) <= 14 && Abs(gg - rr) <= 14)
                trackHits++
            if (Abs(bb - rr) <= 16
                && ((gg > bb + 10 && gg > rr + 10 && gg > 62)
                    || (Abs(gg - bb) <= 12 && gg >= 62 && gg <= 170)))
                zc++
            if (bb > 110 && bb > rr + 60 && gg > rr + 30)
                fc++
            else if (rr > 140 && gg > 90 && bb < 130 && rr > bb + 60 && gg > bb + 20)
                cc++
        }
        if (zc >= zThr) {
            if (zl < 0)
                zl := x
            zr := x
            nz++
        }
        if (fc >= fThr) {
            if (fs < 0) {
                fs := x
                fe := x
            } else if (x - fe > 4) {
                if (fe - fs > bfLen) {
                    bfLen := fe - fs
                    bfS := fs
                    bfE := fe
                }
                fs := x
                fe := x
            } else {
                fe := x
            }
        }
        if (chestMinW > 0 && cc >= cThr) {
            if (cs < 0) {
                cs := x
                ce := x
            } else if (x - ce > 4) {
                if (ce - cs > bcLen) {
                    bcLen := ce - cs
                    bcS := cs
                    bcE := ce
                }
                cs := x
                ce := x
            } else {
                ce := x
            }
        }
        x += 2
    }
    if (fs >= 0 && fe - fs > bfLen) {
        bfLen := fe - fs
        bfS := fs
        bfE := fe
    }
    if (cs >= 0 && ce - cs > bcLen) {
        bcLen := ce - cs
        bcS := cs
        bcE := ce
    }

    if (nz < 2)
        return 0
    if (total && trackHits / total < 0.10)               ; track background gone
        return 0

    fl := (bfLen >= 2) ? bfS : -1
    fr := (bfLen >= 2) ? bfE + 2 : -1
    cl := -1, cr := -1
    if (chestMinW > 0 && bcLen >= 0 && (bcE - bcS + 2) >= Max(3, chestMinW)) {
        cl := bcS
        cr := bcE + 2
    }
    zr += 2

    ; A tile clipping one end of the zone hides that edge: rebuild it.
    if (zoneWRef > 0 && (zr - zl) < zoneWRef - 8 * BotState.sc) {
        leftHit := (fl >= 0 && fl <= zl + 6) || (cl >= 0 && cl <= zl + 6)
        rightHit := (fr >= 0 && fr >= zr - 6) || (cr >= 0 && cr >= zr - 6)
        if (leftHit && !rightHit)
            zl := zr - zoneWRef
        else if (rightHit && !leftHit)
            zr := zl + zoneWRef
    }
    return {zl: zl, zr: zr, fl: fl, fr: fr, cl: cl, cr: cr}
}

; Fraction (0..1) of the progress bar that is filled, or -1 if unreadable.
ReadProgress(geo) {
    bits := geo.grab.bits
    w := geo.tw
    maxX := -1, cnt := 0
    x := 0
    while (x < w) {
        hit := 0
        for ry in geo.progRows {
            v := NumGet(bits, (ry * w + x) * 4, "UInt")
            rr := (v >> 16) & 255
            gg := (v >> 8) & 255
            bb := v & 255
            if (gg > 150 && bb < 145 && rr < 185)
                hit++
        }
        if (hit >= 1) {
            cnt++
            maxX := x
        }
        x += 2
    }
    if (cnt < 3)
        return -1
    return Min(1.0, (maxX + 2) / w)
}

; The honest "minigame still up" witness: the two-tone strip spans the track.
ProgressPresent(geo) {
    bits := geo.grab.bits
    w := geo.tw
    ry := geo.progRows[2]
    n := 0, hit := 0
    x := 0
    while (x < w) {
        v := NumGet(bits, (ry * w + x) * 4, "UInt")
        rr := (v >> 16) & 255
        gg := (v >> 8) & 255
        bb := v & 255
        n++
        if (gg > bb + 15 && gg > rr + 15 && gg > 40)
            hit++
        x += 4
    }
    return n && (hit / n) >= 0.5
}

; Bite marker: a magenta-pink ring + "!" (hue 316..358 deg, S>=45/255, V>=110).
; Same method as the Python build: colour mask -> connected blobs (small gaps
; closed) -> shape gates on each blob, so stray pink pixels can't spoil it.
; The "!" marker. Measured on a real RDP frame: its body is SALMON (248,117,130);
; only the anti-aliased edge blends towards pink/purple (170,102,143). The old
; rule matched only that edge (114 of ~3,300 marker pixels), so detection depended
; on what was behind the marker. In an RDP session both looks are accepted; on a
; normal desktop the original rule is used unchanged.
IsBitePx(rr, gg, bb) {
    if (rr < 110)
        return false
    if (Rdp.on && rr >= 200 && gg >= 60 && gg <= 165 && bb >= 70 && bb <= 175 && rr - gg >= 70 && Abs(bb - gg) <= 45)
        return true                                        ; salmon body (RDP colour pipeline only)
    if (bb > gg && rr >= bb) {                             ; pink edge (previous rule)
        d := rr - gg
        e := bb - gg
        return (d * 17 >= 3 * rr && e * 100 <= 73 * d && e * 30 >= d && e >= 40)
    }
    return false
}

; Scan the bite zone once. `ign` (or 0) is a mask of cells that were already
; marker-coloured BEFORE any bite (cape, bobber, rod glow...): they are skipped.
BiteScan(ign := 0) {
    r := SubRect(BotState.win, Regions.bite)
    gr := ScreenGrab.Get(r.w, r.h)
    gr.Capture(r.x, r.y)
    bits := gr.bits
    w := r.w, h := r.h
    st := Max(3, Round(3.5 * BotState.sc))
    gw := (w + st - 1) // st
    gh := (h + st - 1) // st
    mask := Buffer(gw * gh, 0)
    cxs := [], cys := []
    gy := 0
    y := 0
    while (y < h) {
        row := y * w * 4
        gx := 0
        x := 0
        while (x < w) {
            v := NumGet(bits, row + x * 4, "UInt")
            if IsBitePx((v >> 16) & 255, (v >> 8) & 255, v & 255) {
                o := gy * gw + gx
                if !(ign && NumGet(ign, o, "UChar")) {
                    NumPut("UChar", 1, mask, o)
                    cxs.Push(gx)
                    cys.Push(gy)
                }
            }
            x += st
            gx++
        }
        y += st
        gy++
    }
    return {mask: mask, gw: gw, gh: gh, cxs: cxs, cys: cys, w: w, h: h, st: st, bits: bits}
}

; Called once per cast, right before waiting for the bite. Two frames 150 ms apart:
; a cell that is marker-coloured in BOTH is scenery, not a bite. Grown by one cell
; so a 1-px shake of the camera does not matter.
BiteBaseline() {
    BotState.biteBase := 0
    BotState.biteBaseN := 0
    a := BiteScan()
    Sleep(150)
    b := BiteScan()
    if (a.gw != b.gw || a.gh != b.gh)
        return
    gw := b.gw, gh := b.gh
    base := Buffer(gw * gh, 0)
    n := 0
    Loop b.cxs.Length {
        i := A_Index
        x := b.cxs[i], y := b.cys[i]
        if !NumGet(a.mask, y * gw + x, "UChar")
            continue
        n++
        ny := Max(0, y - 1)
        while (ny <= Min(gh - 1, y + 1)) {
            nx := Max(0, x - 1)
            while (nx <= Min(gw - 1, x + 1)) {
                NumPut("UChar", 1, base, ny * gw + nx)
                nx++
            }
            ny++
        }
    }
    if n {
        BotState.biteBase := base
        BotState.biteBaseN := n
    }
}

; Keep the frame that fired a bite, so a false hook can be inspected afterwards.
BiteKeep(s, box) {
    sz := s.w * s.h * 4
    if (!IsObject(BotState.biteFrame) || BotState.biteFrame.Size != sz)
        BotState.biteFrame := Buffer(sz)
    DllCall("RtlMoveMemory", "ptr", BotState.biteFrame, "ptr", s.bits, "uptr", sz)
    BotState.biteFrameW := s.w
    BotState.biteFrameH := s.h
    BotState.biteBox := box
}

; Write the kept frame to a PNG. Returns the path or "".
BiteDumpFrame() {
    f := BotState.biteFrame
    if (!IsObject(f) || !Gp.Start())
        return ""
    bmp := 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", BotState.biteFrameW, "int", BotState.biteFrameH
        , "int", BotState.biteFrameW * 4, "int", 0x22009, "ptr", f, "ptr*", &bmp)
    if !bmp
        return ""
    path := TMP_DIR . "\bite_false_" . FormatTime(, "HHmmss") . ".png"
    box := BotState.biteBox
    boxed := false
    if IsObject(box) {
        graphics := 0, pen := 0
        if (DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", bmp, "ptr*", &graphics) == 0 && graphics) {
            if (DllCall("gdiplus\GdipCreatePen1", "uint", 0xFFFF2020, "float", Max(3, Round(3 * BotState.sc)), "int", 2, "ptr*", &pen) == 0 && pen) {
                ; Draw twice to keep the detector bounds visible after Discord scales the image.
                drawOk := true
                Loop 2 {
                    pad := A_Index - 1
                    status := DllCall("gdiplus\GdipDrawRectangleI", "ptr", graphics, "ptr", pen
                        , "int", Max(0, box.x - pad), "int", Max(0, box.y - pad)
                        , "int", Min(BotState.biteFrameW - box.x, box.w + 2 * pad)
                        , "int", Min(BotState.biteFrameH - box.y, box.h + 2 * pad))
                    if status
                        drawOk := false
                }
                boxed := drawOk
                DllCall("gdiplus\GdipDeletePen", "ptr", pen)
            }
            DllCall("gdiplus\GdipDeleteGraphics", "ptr", graphics)
        }
    }
    if !boxed {
        DllCall("gdiplus\GdipDisposeImage", "ptr", bmp)
        return ""
    }
    ok := (DllCall("gdiplus\GdipSaveImageToFile", "ptr", bmp, "wstr", path, "ptr", Gp.clsid, "ptr", 0) == 0)
    DllCall("gdiplus\GdipDisposeImage", "ptr", bmp)
    return (ok && FileExist(path)) ? path : ""
}

BiteNow() {
    s := BiteScan(BotState.biteBase)
    n := s.cxs.Length
    gw := s.gw, gh := s.gh, mask := s.mask, cxs := s.cxs, cys := s.cys
    w := s.w, h := s.h, st := s.st
    BotState.biteInfo := "marker cells=" . n . (BotState.biteBaseN ? " (" . BotState.biteBaseN . " static ignored)" : "")
    if (n < 4 || n > 12000)
        return false

    seen := Buffer(gw * gh, 0)
    gap := 2                                   ; cells: bridges ~8 px gaps (the "close")
    minDim := w * 0.055
    areaFloor := 6e-4 * w * h
    bestDim := 0
    Loop n {
        i := A_Index
        sx := cxs[i], sy := cys[i]
        if NumGet(seen, sy * gw + sx, "UChar")
            continue
        NumPut("UChar", 1, seen, sy * gw + sx)
        stack := [[sx, sy]]
        cnt := 0
        minX := sx, maxX := sx, minY := sy, maxY := sy
        while stack.Length {
            c := stack.Pop()
            px := c[1], py := c[2]
            cnt++
            if (px < minX)
                minX := px
            if (px > maxX)
                maxX := px
            if (py < minY)
                minY := py
            if (py > maxY)
                maxY := py
            ny := Max(0, py - gap)
            while (ny <= Min(gh - 1, py + gap)) {
                nx := Max(0, px - gap)
                while (nx <= Min(gw - 1, px + gap)) {
                    o := ny * gw + nx
                    if (NumGet(mask, o, "UChar") && !NumGet(seen, o, "UChar")) {
                        NumPut("UChar", 1, seen, o)
                        stack.Push([nx, ny])
                    }
                    nx++
                }
                ny++
            }
        }
        bw := (maxX - minX + 1) * st
        bh := (maxY - minY + 1) * st
        area := cnt * st * st
        bestDim := Max(bestDim, Max(bw, bh))
        if (Max(bw, bh) < minDim || area < areaFloor)
            continue
        aspect := bw / bh
        if (aspect <= 0.40 || aspect >= 2.30)
            continue
        if (area / (bw * bh) < 0.10)
            continue
        BotState.biteInfo := "marker " . bw . "x" . bh . " px at " . (minX * st) . "," . (minY * st)
        BiteKeep(s, {x: Max(0, minX * st - 8), y: Max(0, minY * st - 8)
            , w: Min(w - Max(0, minX * st - 8), bw + 16), h: Min(h - Max(0, minY * st - 8), bh + 16)})
        return true
    }
    BotState.biteInfo := "marker cells=" . n . " largest blob=" . bestDim . " px (need " . Round(minDim) . ")"
    return false
}

; ---- cast charge meter -------------------------------------------------------
; The meter is a dark vertical track with a black outline. Its fill grows upward
; from the bottom and changes colour as it charges: ORANGE (255,151,0) at the
; bottom -> yellow -> green at the top. The bar then bounces back down, so the
; only reliable signal is the fill level measured against the track height.
IsMeterFill(c) {
    rr := (c >> 16) & 255
    gg := (c >> 8) & 255
    bb := c & 255
    mx := Max(rr, gg)
    return bb < 90 && mx > 140 && (mx - bb) > 110
}

IsMeterEdge(c) {                                       ; the black outline (measured 0-15; the track interior is 28-36)
    return Max((c >> 16) & 255, (c >> 8) & 255, c & 255) <= 20
}

IsMeterTrack(c) {                                      ; empty track: dark blue-grey, bluer over bright sky/sea (25,55,69)
    rr := (c >> 16) & 255
    gg := (c >> 8) & 255
    bb := c & 255
    mx := Max(rr, gg, bb)
    return mx > 20 && mx <= 125 && (mx - Min(rr, gg, bb)) <= 64
}

MeterReset() {
    Meter.x := 0
    Meter.top := 0
    Meter.bot := 0
}

; Measure the track around a seed pixel that has a fill colour. Stores the track
; geometry in Meter and returns true, or returns false for look-alikes (yellow
; clothes, a hat ...): a real meter has a black outline on both sides and above.
MeterMeasure(sx, sy) {
    win := BotState.win
    H := win.h
    ys := sy - win.y
    if (ys < 0 || ys >= H)
        return false
    gr := ScreenGrab.Get(1, H)
    gr.Capture(sx, win.y)
    bits := gr.bits

    ; up to the top outline
    y := ys, miss := 0, top := -1
    while (y >= 0) {
        c := NumGet(bits, y * 4, "UInt")
        if IsMeterEdge(c) {
            edgeLow := y
            top := edgeLow + 1                         ; first interior row
            break
        }
        if (IsMeterFill(c) || IsMeterTrack(c)) {
            miss := 0
        } else if (++miss > 2) {
            return false
        }
        y--
    }
    if (top < 0)
        return false

    ; down to the bottom outline (or the last bar-coloured row if it is hidden)
    y := ys, miss := 0
    bot := -1, lastBar := ys
    while (y < H) {
        c := NumGet(bits, y * 4, "UInt")
        if IsMeterEdge(c) {
            bot := y - 1
            break
        }
        if (IsMeterFill(c) || IsMeterTrack(c)) {
            lastBar := y
            miss := 0
        } else if (++miss > 2) {
            bot := lastBar
            break
        }
        y++
    }
    if (bot < 0)
        bot := lastBar
    hgt := bot - top + 1
    if (hgt < Round(H * 0.07) || hgt > Round(H * 0.40))
        return false

    ; width: an outline on both sides of the seed
    half := Round(win.w * 0.025)
    rowW := half * 2 + 1
    gr2 := ScreenGrab.Get(rowW, 1)
    gr2.Capture(sx - half, sy)
    left := -1, right := -1
    i := half
    while (i >= 0) {
        if IsMeterEdge(NumGet(gr2.bits, i * 4, "UInt")) {
            left := i
            break
        }
        i--
    }
    i := half
    while (i < rowW) {
        if IsMeterEdge(NumGet(gr2.bits, i * 4, "UInt")) {
            right := i
            break
        }
        i++
    }
    if (left < 0 || right < 0)
        return false
    wid := right - left
    if (wid < Round(win.w * 0.004) || wid > Round(win.w * 0.022))
        return false

    Meter.x := sx - half + (left + right) // 2
    Meter.top := win.y + top
    Meter.bot := win.y + bot
    return true
}

; Locate the meter inside one region: native PixelSearch for the fill colours
; (orange, dark orange, amber, yellow, yellow-green, green), top-most hit first.
MeterFind(fr) {
    win := BotState.win
    r := SubRect(win, fr)
    x1 := r.x, y1 := r.y
    x2 := r.x + r.w, y2 := r.y + r.h
    cols := [0xFF9700, 0xCA7700, 0xFFCC00, 0xF0FF00, 0xB7C300, 0x1FF910, 0xAAFF00, 0x84C500, 0x6EFF08]
    Loop 60 {
        top := 99999, tx := 0
        for col in cols {
            if PixelSearch(&fx, &fy, x1, y1, x2, y2, col, 30) && fy < top {
                top := fy
                tx := fx
            }
        }
        if (top == 99999)
            return false
        if MeterMeasure(tx, top)
            return true
        y1 := top + 8                                  ; false hit: look below it
        if (y1 >= y2)
            break
    }
    return false
}

; Fill level 0..1 (1 = completely full), or -1 when no meter is on screen.
; Once located, only a 1-px wide column through the track is read per tick.
MeterRead() {
    Loop 2 {
        if (Meter.x > 0) {
            h := Meter.bot - Meter.top + 1
            gr := ScreenGrab.Get(1, h)
            gr.Capture(Meter.x, Meter.top)
            bits := gr.bits
            mid := NumGet(bits, (h // 2) * 4, "UInt")
            if (IsMeterFill(mid) || IsMeterTrack(mid)) {
                fillTop := h, miss := 0, seen := false
                i := h - 1
                while (i >= 0) {
                    if IsMeterFill(NumGet(bits, i * 4, "UInt")) {
                        fillTop := i
                        seen := true
                        miss := 0
                    } else if (++miss > 3) {
                        break
                    }
                    i--
                }
                return seen ? (h - fillTop) / h : 0.0
            }
            MeterReset()                               ; track vanished: search again
        }
        if !(MeterFind(Regions.meter) || MeterFind(Regions.meterWide))
            return -1
    }
    return -1
}

; Recipe note: navy "Learn" button carrying white text.
LearnUp() {
    r := SubRect(BotState.win, Regions.learn)
    gr := ScreenGrab.Get(r.w, r.h)
    gr.Capture(r.x, r.y)
    bits := gr.bits
    n := 0, navy := 0, white := 0
    y := 0
    while (y < r.h) {
        x := 0
        while (x < r.w) {
            v := NumGet(bits, (y * r.w + x) * 4, "UInt")
            rr := (v >> 16) & 255
            gg := (v >> 8) & 255
            bb := v & 255
            n++
            if (bb > 70 && bb < 160 && gg > 30 && gg < 100 && rr < 70 && bb > rr + 45)
                navy++
            else if (bb > 200 && gg > 200 && rr > 200)
                white++
            x += 3
        }
        y += 3
    }
    return n && navy / n >= 0.45 && white / n >= 0.01
}

; Yellow "Craft" action button present? It is a clean solid block, so require
; a stack of consecutive rows that are mostly yellow (clothes and hats are not).
CraftUp() {
    win := BotState.win
    r := SubRect(win, Regions.craft)
    gr := ScreenGrab.Get(r.w, r.h)
    gr.Capture(r.x, r.y)
    bits := gr.bits
    minW := r.w * 0.25
    minRows := Max(16, Round(win.h * 0.022))
    run := 0, bad := 0, runFirst := -1
    y := 0
    while (y < r.h) {
        first := -1, last := -1, cnt := 0
        x := 0
        while (x < r.w) {
            v := NumGet(bits, (y * r.w + x) * 4, "UInt")
            rr := (v >> 16) & 255
            gg := (v >> 8) & 255
            bb := v & 255
            if (rr > 180 && gg > 150 && bb < 110) {
                if (first < 0)
                    first := x
                last := x
                cnt++
            }
            x += 2
        }
        if (first >= 0 && (last - first) >= minW && cnt * 2 >= (last - first) * 0.55
            && (runFirst < 0 || Abs(first - runFirst) <= 8 * BotState.sc)) {
            if (run == 0)
                runFirst := first
            run += 2
            bad := 0
            if (run >= minRows)
                return true
        } else if (++bad > 2) {
            run := 0
            runFirst := -1
        }
        y += 2
    }
    return false
}

; The NPC name banner ("Fisherman") of the dialogue: a long warm-yellow band in
; the lower centre of the screen. Same rule as the Python build.
DialogueHeader() {
    win := BotState.win
    r := SubRect(win, [0.25, 0.52, 0.75, 0.92])
    gr := ScreenGrab.Get(r.w, r.h)
    gr.Capture(r.x, r.y)
    bits := gr.bits
    minWidth := Round(win.w * 0.18)
    minRows := Max(8, Round(win.h * 0.008))
    run := 0
    y := 0
    while (y < r.h) {
        first := -1, last := -1, cnt := 0
        x := 0
        while (x < r.w) {
            v := NumGet(bits, (y * r.w + x) * 4, "UInt")
            rr := (v >> 16) & 255
            gg := (v >> 8) & 255
            bb := v & 255
            if (rr > 70 && gg > 50 && bb < 130 && rr >= gg && rr > bb + 30 && gg > bb + 20) {
                if (first < 0)
                    first := x
                last := x
                cnt++
            }
            x += 3
        }
        span := last - first
        if (first >= 0 && span >= minWidth && cnt * 3 >= span * 0.45) {
            run += 2
            if (run >= minRows)
                return true
        } else {
            run := 0
        }
        y += 2
    }
    return false
}

; Update 30 NPC menu. The button panels are an opaque, flat slate (~RGB 21..34, 30..40, 37..41)
; whatever the sea or sky looks like, so panels are found by that colour, not by
; "darkness" (a night sea is just as dark). A hovered button changes colour, so a
; panel whose fill is missing is still recovered from its white icon.
; Returns an array of {x, y} click targets (absolute), top to bottom, or [].
IsPanelFill(rr, gg, bb) {
    return Abs(rr - 27) <= 10 && Abs(gg - 35) <= 9 && Abs(bb - 40) <= 8   ; covers 21..37 / 26..44 / 32..48
}

MenuPanelsFill() {
    win := BotState.win
    r := SubRect(win, Regions.menu)
    gr := ScreenGrab.Get(r.w, r.h)
    gr.Capture(r.x, r.y)
    bits := gr.bits
    w := r.w, h := r.h
    colStep := 4
    cols := (w + colStep - 1) // colStep
    nrows := (h + 1) // 2
    need := Max(8, Floor(cols * 0.30))
    minH := Max(18, Floor(h * 0.09))
    maxH := Max(minH + 1, Floor(h * 0.40))

    ; ---- 1. bands of panel-fill colour -------------------------------------
    counts := []
    counts.Length := nrows
    ri := 0
    y := 0
    while (y < h) {
        n := 0
        base := y * w * 4
        x := 0
        while (x < w) {
            v := NumGet(bits, base + x * 4, "UInt")
            if IsPanelFill((v >> 16) & 255, (v >> 8) & 255, v & 255)
                n++
            x += colStep
        }
        ri++
        counts[ri] := n
        y += 2
    }
    panels := []
    start := -1, lastOn := -1
    Loop nrows + 1 {
        i := A_Index
        on := (i <= nrows) && counts[i] >= need
        yy := (i - 1) * 2
        if on {
            if (start < 0)
                start := yy
            lastOn := yy
        } else if (start >= 0 && (i > nrows || yy - lastOn > 4)) {
            hgt := lastOn - start + 1
            if (hgt >= minH && hgt <= maxH) {
                t := PanelTarget(bits, w, colStep, r, start, lastOn)
                t.top := start
                t.bot := lastOn
                panels.Push(t)
            }
            start := -1
        }
    }

    ; ---- 2. hover recovery: white icon blobs without a fill band ------------
    if panels.Length {
        ix0 := Max(0, Round(win.w * 0.696) - (r.x - win.x))
        ix1 := Min(w - 1, Round(win.w * 0.735) - (r.x - win.x))
        iconMin := Max(12, Floor(win.h * 0.030))
        iconMax := Floor(win.h * 0.065)
        bs := -1, bl := -1
        added := []
        y := 0
        while (y <= h) {
            on := false
            if (y < h) {
                wc := 0
                x := ix0
                while (x <= ix1) {
                    v := NumGet(bits, (y * w + x) * 4, "UInt")
                    if (Min((v >> 16) & 255, (v >> 8) & 255, v & 255) >= 225)
                        wc++
                    x += 2
                }
                on := wc >= 5
            }
            if on {
                if (bs < 0)
                    bs := y
                bl := y
            } else if (bs >= 0 && (y >= h || y - bl > 4)) {
                hh := bl - bs + 1
                if (hh >= iconMin && hh <= iconMax) {
                    ym := (bs + bl) // 2
                    covered := false
                    for q in panels {
                        if (ym >= q.top - 6 && ym <= q.bot + 6)
                            covered := true
                    }
                    if !covered
                        added.Push({x: r.x + ix1 + Round(150 * BotState.sc), y: r.y + ym, top: ym - 20, bot: ym + 20})
                }
                bs := -1
            }
            y += 2
        }
        for a in added
            panels.Push(a)
        ; keep top-to-bottom order
        Loop panels.Length - 1 {
            i := A_Index + 1
            key := panels[i]
            j := i - 1
            while (j >= 1 && panels[j].y > key.y) {
                panels[j + 1] := panels[j]
                j--
            }
            panels[j + 1] := key
        }
    }
    return panels.Length >= 2 ? panels : []
}

; Menu buttons, found two ways. The fill colour changes with the scenery behind
; the (translucent) buttons, but the outline does not: 4 px of pure black for
; an active button, neutral grey 72 for a LOCKED one. The better result wins.
MenuPanels() {
    a := MenuPanelsFill()
    b := MenuPanelsBorder()
    if (Cfg.npc == "Angler")
        return (b.Length >= a.Length) ? b : a
    return (a.Length >= b.Length) ? a : b
}

MenuPanelsBorder() {
    win := BotState.win
    r := SubRect(win, Regions.menu)
    gr := ScreenGrab.Get(r.w, r.h)
    gr.Capture(r.x, r.y)
    bits := gr.bits
    w := r.w, h := r.h
    colStep := 4
    cols := (w + colStep - 1) // colStep
    need := Max(8, Floor(cols * 0.30))
    maxThick := Max(6, Round(win.h * 0.009))

    ; ---- 1. horizontal outline lines ---------------------------------------
    groups := []
    gs := -1, gl := -1, gxs := 0, gxe := 0
    y := 0
    while (y <= h) {
        on := false
        xs := -1, xe := -1
        if (y < h) {
            n := 0
            base := y * w * 4
            x := 0
            while (x < w) {
                v := NumGet(bits, base + x * 4, "UInt")
                rr := (v >> 16) & 255
                gg := (v >> 8) & 255
                bb := v & 255
                if (Max(rr, gg, bb) <= 8
                    || (Abs(rr - 72) <= 5 && Abs(gg - 72) <= 5 && Abs(bb - 72) <= 5)) {
                    n++
                    if (xs < 0)
                        xs := x
                    xe := x
                }
                x += colStep
            }
            on := (n >= need)
        }
        if on {
            if (gs < 0) {
                gs := y
                gxs := xs
                gxe := xe
            } else {
                gxs := Min(gxs, xs)
                gxe := Max(gxe, xe)
            }
            gl := y
        } else if (gs >= 0 && (y >= h || y - gl > 3)) {
            if (gl - gs + 1 <= maxThick)                ; thick black areas are not outlines
                groups.Push({s: gs, e: gl, xs: gxs, xe: gxe})
            gs := -1
        }
        y++
    }

    ; ---- 2. top line + bottom line = one button -----------------------------
    panels := []
    pmin := win.h * 0.060
    pmax := win.h * 0.100
    i := 1
    while (i < groups.Length) {
        a := groups[i]
        b := groups[i + 1]
        span := b.e - a.s + 1
        if (span >= pmin && span <= pmax) {
            xs := Min(a.xs, b.xs)
            xe := Max(a.xe, b.xe)
            panels.Push({x: r.x + xs + Round((xe - xs) * 0.40), y: r.y + (a.s + b.e) // 2
                       , top: a.s, bot: b.e})
            i += 2
        } else {
            i++
        }
    }
    return panels.Length >= 2 ? panels : []
}

; Click point: 40 % into the fill span of the panel's middle row.
PanelTarget(bits, w, colStep, r, y0, y1) {
    ym := (y0 + y1) // 2
    xs := -1, xe := -1
    x := 0
    while (x < w) {
        v := NumGet(bits, ym * w * 4 + x * 4, "UInt")
        if IsPanelFill((v >> 16) & 255, (v >> 8) & 255, v & 255) {
            if (xs < 0)
                xs := x
            xe := x
        }
        x += colStep
    }
    if (xs < 0)
        return {x: r.x + w // 2, y: r.y + ym}
    return {x: r.x + xs + Round((xe - xs) * 0.40), y: r.y + ym}
}

PanelSig(panels) {
    s := panels.Length . ":"
    for p in panels
        s .= (p.y // 4) . ","
    return s
}
