# Hull Construction Guide — ASV Catamaran
**Project:** GPS-Denied Acoustic Homing USV  
**Deadline:** August 10, 2026 — pool test #1 fixed at Week 9 (Jul 20)  
**Reference diagrams:** `docs/diagrams/vehicle_top_view.svg`, `vehicle_side_view.svg`

---

## Materials Checklist (Home Depot run — complete by Jun 30)

| Item | Qty | Notes |
|------|-----|-------|
| 4" Schedule 40 PVC pipe | ~1.5 m | Cut into 2× 700 mm pontoons |
| 1" PVC pipe | ~1.2 m | 3× 440 mm cross members + 300 mm mast + 165 mm bow brace |
| 4" PVC end caps | 4 | Seal pontoon ends — MUST be glued and siliconed |
| Aluminum L-brackets (2" × 2") | 10 | Cross-member-to-pontoon attachment |
| Marine plywood 12 mm or 1/8" Al sheet | ~500 × 350 mm | Deck platform |
| JB Weld MarineWeld | 1 kit | Structural bonds at all PVC joints |
| Marine silicone (clear, waterproof) | 1 tube | Secondary seal on end caps and gland entry points |
| M4 bolts + nuts + washers | 20 | L-bracket fastening |
| M3 standoffs (10 mm) | 8 | Electronics enclosure mounting to deck |
| Hose clamps (1" band) | 6 | Cross member clamping to pontoons |
| Zip ties (heavy duty) | 20 | Secondary cable management |
| Sandpaper (80 + 220 grit) | 1 sheet each | Surface prep before bonding |

**Also needed (already owned or on order):**
- Otdorpatio IP67 enclosure 160×160×90 mm (ordered Jun 26)
- Additional M16/M12 cable glands ×4-pack (order with MCP6022)
- LICHIFIT RF-370 thruster mounts (arrives with motors)

---

## Phase 1 — Cut and Label All PVC (30 min)

**Goal:** All pieces cut to final length before any glue touches anything.

1. Mark each cut with masking tape + permanent marker before cutting.
2. Cut 4" Sch 40 PVC pipe into **2× 700 mm pontoons**. Label: "PORT" and "STBD".
3. Cut 1" PVC pipe into:
   - **3× 440 mm** cross members (label CM1, CM2, CM3)
   - **1× 165 mm** bow brace
   - **1× 280 mm** mast (will extend 280 mm above waterline — may trim after float test)
4. Deburr all cuts with 80-grit sandpaper, then smooth with 220-grit.
5. Dry-fit all pieces on a flat surface and confirm against diagram dimensions before proceeding.

> **Check:** Lay both pontoons parallel, 400 mm apart (centerline to centerline). Place cross members across at 150 mm, 350 mm, and 550 mm from one end. Everything should sit flat.

---

## Phase 2 — Waterproof Pontoon Ends (1 hr + 24 hr cure)

**Goal:** Both pontoons sealed and pressure-tested before assembly.

1. Clean the inside rim of each pontoon end with 220-grit sandpaper. Wipe with a dry cloth.
2. Apply a ring of JB Weld MarineWeld to the rim of one 4" end cap. Press firmly onto pontoon end.
3. Apply a bead of marine silicone around the outside joint as a secondary seal.
4. Repeat for all 4 end caps (both ends of both pontoons).
5. Let cure **24 hours minimum** before proceeding.
6. **Pressure test:** Close one end, blow air into the other end while submerging in a tub. No bubbles = sealed. Fix any leaks before hull assembly.

> **Why it matters:** A leaking pontoon destroys buoyancy. If a pontoon floods, the electronics bay goes underwater. Test before assembly, not after.

---

## Phase 3 — Dry-Fit and Drill L-Bracket Holes (45 min)

**Goal:** All hole positions confirmed before permanent bonding.

1. Place both pontoons on a flat surface, parallel, 400 mm apart (CL to CL).
2. Lay CM1 across the pontoons at the **150 mm mark** from bow. Mark the contact points on both pontoons with a marker.
3. Repeat for CM2 (350 mm) and CM3 (550 mm).
4. At each contact point, position an L-bracket so one face lies flat on the pontoon top and the other face grips the cross member. Mark the bolt holes.
5. Drill M4 holes through the pontoon wall at each bracket position (use a sharp bit, slow speed to avoid cracking PVC).
6. Dry-assemble entire frame with bolts and brackets — no adhesive yet. Check that the frame is square (diagonal measurements should be equal) and sits flat on a surface.

> **Check:** Both pontoons must be parallel and level. Use a spirit level on each cross member. Fix any skew now — it is nearly impossible to correct after gluing.

---

## Phase 4 — Permanent Assembly (1 hr + 24 hr cure)

**Goal:** Fully bonded and squared hull frame.

1. Disassemble the dry-fit.
2. Apply JB Weld MarineWeld to the pontoon surface at each cross-member contact point (the area under the L-bracket face and under the cross member OD).
3. Apply marine silicone along the full contact line of each cross member where it touches the pontoon.
4. Reassemble with L-brackets and M4 bolts. Torque snugly but do not over-torque (PVC cracks).
5. Add a hose clamp around each cross member at each pontoon junction for extra retention.
6. Re-check square: diagonals equal, frame flat. Clamp or brace as needed while curing.
7. Cure **24 hours minimum**. Do not load the frame until fully cured.

---

## Phase 5 — Deck Platform Installation (30 min + cure)

**Goal:** Flat mounting surface for enclosure and mast, sitting on top of the three cross members.

1. Cut deck platform material (12 mm marine ply or 1/8" Al sheet) to **440 × 314 mm** (to fit between CM1 and CM3 edges, and between pontoon inner edges).
2. If using plywood, seal all edges with two coats of marine epoxy or exterior polyurethane — leave no bare wood exposed.
3. Drill M3 standoff holes through the platform at the four enclosure corner positions (see top-view diagram for centering: enclosure is 160×160 mm centered on the platform).
4. Lay platform on top of CM1–CM3. Mark the cross member contact lines on the underside.
5. Drill M4 clearance holes through the platform at the cross-member lines and bolt through into the cross members.
6. Apply thin bead of marine silicone between the platform and each cross member top face before final bolting.
7. Attach M3 standoffs (10 mm) at enclosure mounting corners — these raise the enclosure slightly above the deck for airflow and allow cable egress underneath.

---

## Phase 6 — Mast and Bow Brace Installation (30 min)

**Goal:** Mast mounted at bow, vertical, braced to the forward edge of the deck platform.

1. Cut the mast to 280 mm (will rise 280 mm above waterline — adjust after float test if needed).
2. Attach the 165 mm bow brace horizontally at the level of the deck top, connecting from the mast foot to the CM1 face. Use two L-brackets and JB Weld.
3. Check mast is vertical (use a small spirit level). Clamp while adhesive cures.
4. Mount the TCT40-16R transducer bracket at the top of the mast. The transducer face must point forward (toward the buoys) and be at least 250 mm above the waterline.
5. Run the RX signal coax from the transducer down the mast (zip-tie to the mast pipe every 50 mm), then along the deck to the cable gland entry point on the enclosure.

---

## Phase 7 — Thruster Mounting (30 min — AFTER stall-current bench test passes)

> **GATE: Do NOT mount thrusters until ESP32 stall-current trip firmware is confirmed working and actual stall current has been bench-measured. Epoxying a thruster is irreversible.**

1. Mark thruster mounting position on each pontoon stern: 20–30 mm from the aft end cap, on the bottom of the pontoon.
2. Drill mounting holes per the LICHIFIT RF-370 mount template.
3. Pass motor leads through a cable gland in the pontoon (seal with marine silicone).
4. Bed the thruster mount with JB Weld MarineWeld before bolting.
5. Seal around the entire mount/gland joint with marine silicone. No gaps.
6. Cure 24 hours before first water contact.

---

## Phase 8 — Float Test and Waterline Verification (30 min)

**Goal:** Confirm actual float depth and trim before mounting electronics.

1. Place the bare hull (no electronics) in a tub or pool. Record:
   - Actual waterline position on pontoon (should be near mid-diameter)
   - Trim (bow/stern level) — add ballast weight to equalize if needed
2. Mark the actual waterline on each pontoon with a permanent marker.
3. Measure the actual height of the deck platform above the waterline (target ≥ 80 mm — enclosure must stay dry in calm conditions).
4. If deck is less than 60 mm above WL: shorten cross members or add extension risers to raise the deck.
5. Repeat float test with the electronics enclosure (filled with equivalent dead weight ~400 g) placed on the standoffs to confirm the loaded waterline.

> **Target:** Enclosure bottom ≥ 60 mm above waterline. Pontoon top ≥ 40 mm above waterline.

---

## Phase 9 — Cable Glands and Enclosure Sealing (1 hr)

**Goal:** Waterproof penetrations for all cables before electronics are installed.

1. Mark the 7 cable gland positions on the enclosure walls (see `wiring_overview.svg`):
   - Motor bundle × 2 (port and stbd, 14 AWG)
   - JSN-SR04T cable
   - Mast RX coax
   - LiPo XT60 power cable (12 AWG)
   - UART/signal wire bundle
   - Spare plugged gland
2. Drill gland holes with a step drill. Test-fit each M16 gland before final assembly.
3. Route all cables, cinch the gland lock rings finger-tight for now.
4. Load electronics into enclosure (Pi, Tang Nano, preamp breadboard, wiring).
5. Torque all gland lock rings firmly. Apply a small bead of marine silicone around the outside of each gland as a backup seal.
6. Close the enclosure lid. IP67 gasket must seat fully in its groove — inspect all four sides.

---

## Phase 10 — Final Integration Check (1 hr)

Before first water test with electronics:

- [ ] All gland lock rings torqued; silicone bead applied externally
- [ ] Enclosure lid gasket seated, lid bolts torqued evenly
- [ ] All motor leads connected to L298N and strain-relieved inside enclosure
- [ ] JSN-SR04T 1kΩ/2kΩ ECHO divider in place (5V → 3.3V)
- [ ] Star ground confirmed: preamp/ADC ground separated from motor ground, joined only at LiPo negative terminal
- [ ] PV-1/PV-2/PV-3 cleared on AD9226 (DRVDD=3.3V, DFS=AVSS, OEB=GND) before FPGA powered
- [ ] Buck converter output measured at 4.9–5.1 V under load
- [ ] vcgencmd get_throttled reads 0x0 with all ROS 2 nodes running
- [ ] Thruster stall-current trip confirmed working in firmware before any water test

---

## Estimated Timeline

| Day | Task | Duration |
|-----|------|----------|
| Jun 30 (W6 D2) | Cut PVC, end caps sealed — Home Depot run | 2.5 hr |
| Jul 1  (W6 D3) | Pontoon pressure test; drill and dry-fit frame | 2 hr |
| Jul 2  (W6 D4) | Permanent hull bond; deck platform cut + sealed | 2 hr (+ 24 hr cure) |
| Jul 3  (W6 D5) | Deck and mast installation; float test bare hull | 2 hr |
| Jul 4–5 (W6 D6-7) | Cable glands; enclosure load; final integration check | 3 hr |
| Week 7 | Thruster mounting (after stall-current bench test) | 1 hr |
| Week 8 | Full dry-land E2E rehearsal on completed hull | — |

**Critical path:** End cap cure (Jun 30 → Jul 1) and hull bond cure (Jul 2 → Jul 3) are the two time-gated waits. Start them as early as possible each day to not lose a day to cure time.
