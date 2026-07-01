# Hull Construction Guide — ASV Catamaran
**Project:** GPS-Denied Acoustic Homing USV
**Deadline:** August 10, 2026 — pool test #1 fixed at Week 9 (Jul 20)
**Design:** Foam-and-Deck Catamaran, Size B (pool noodle pontoons + PVC core rod + plywood deck)
**Reference diagrams:** `docs/diagrams/vehicle_top_view.svg`, `vehicle_side_view.svg`

---

## Materials Checklist (Home Depot run — see `docs/home_depot_list.md` for verified pricing, ~$90–96 total)

| Item | Qty | Notes |
|------|-----|-------|
| Standard pool noodles | 6 | 3 bundled per side (triangular arrangement around core rod) |
| ½" Schedule 40 PVC pipe | ~1.1 m | Cut into 2× 500 mm core rods (one per pontoon) |
| UV-resistant zip ties, 8" | ~24 | Lash noodle bundles to core rod every ~120mm (≈4 per rod × 2 rods, plus spares) |
| ¾" plywood / pressure-treated pine project panel | 1 piece, ≥350×200mm | Deck platform |
| Spray Spar Urethane (Varathane, oil-based, clear) | 1 can | Deck seal — all faces + cut edges, one coat |
| ¾" pine dowel | 1, ~500mm | Mast |
| Aluminum angle stock, 1"×1/16" | ~150mm offcut | Mast L-bracket, drilled |
| Galvanized ½" pipe straps | 4 | Core rod → deck fastening (2 per rod) |
| Wood screws (assorted, #8) | ~12 | Pipe straps + mast L-bracket to deck |
| Stainless M4 bolts + washers | 4 | Enclosure → deck mounting |
| Sandpaper (220 grit) | 1 sheet | Deck edge prep before sealing |

**Also needed (already owned or on order):**
- Otdorpatio IP67 enclosure 160×160×90 mm (ordered Jun 26)
- Additional M16/M12 cable glands ×4-pack (order with MCP6022)
- LICHIFIT RF-370 thruster mounts (arrives with motors)

**Zero structural epoxy/cement in this design.** All hull fasteners are mechanical (zip ties, pipe straps, screws, bolts). The only "cure" step is a passive wood-sealant dry time (hours, same day) — there are no 24-hour structural cure gates.

---

## Phase 1 — Cut and Prep All Components (30 min)

**Goal:** All pieces cut to final length and dry-fit before any assembly.

1. Cut ½" Sch 40 PVC pipe into **2× 500 mm core rods**. Label: "PORT" and "STBD".
2. Cut 6× pool noodles to **500 mm each** (match core rod length).
3. Cut the deck panel to **~350 × 200 mm** from the ¾" plywood/pine project panel.
4. Cut the mast dowel to **~500 mm**.
5. Cut a ~150mm offcut of 1"×1/16" aluminum angle stock for the mast L-bracket; drill mounting holes (2 for deck screws, 1–2 for dowel clamp/screw).
6. Sand all cut edges of the deck panel with 220-grit — this is prep for the sealant coat in Phase 2, not a structural step.
7. Dry-fit: thread each core rod through the hollow center of 3 pool noodles, bundle triangularly, and lay both assemblies parallel at 350mm beam (centerline to centerline) with the deck panel spanning between them. Confirm everything matches the diagram dimensions.

> **Check:** Both core-rod/noodle bundles parallel, 350mm apart (CL to CL). Deck panel (350×200mm) reaches across both rods with margin to spare on each side for the pipe straps.

---

## Phase 2 — Seal the Deck (30 min + same-day dry time)

**Goal:** Deck panel fully sealed against moisture before any hardware is mounted to it.

1. Wipe the sanded deck panel clean of dust.
2. Apply **one coat of spray Spar Urethane (Varathane, oil-based, clear)** to all faces and cut edges of the deck panel. Cover top, bottom, and all four edges — no bare wood exposed.
3. Hang or rest the panel on edge so it doesn't stick to a surface while drying.
4. Let dry per can instructions (typically 1–2 hours to handle-dry, same day). No reapplication needed for the ~4-week August pool-testing window.

> **Why it matters:** This is the only waterproofing step in the entire hull — pool noodle foam is closed-cell and needs zero sealing, and the PVC core rod is inherently waterproof. Get the deck coat even and complete now; it's much harder to touch up once hardware is bolted on.

---

## Phase 3 — Lash Noodle Bundles to Core Rods (30 min)

**Goal:** Both pontoon assemblies rigid and ready to mount to the deck.

1. Thread 3 pool noodles onto each ½" PVC core rod through their hollow centers.
2. Arrange the 3 noodles triangularly around the rod (the rod is the structural spine; the foam provides buoyancy and floats around it).
3. Lash the bundle with UV-resistant 8" zip ties every **~120mm** along the 500mm length (4 ties per rod is typical — adjust to keep the bundle snug and round).
4. Trim excess zip-tie tails flush.
5. Repeat for both PORT and STBD assemblies.

> **Check:** Each bundle should be firm with no noodle slipping along the rod axis. The core rod should not be visible/exposed at any lashing point — foam should fully surround it.

---

## Phase 4 — Mount Core Rods to Deck (30 min)

**Goal:** Both pontoon assemblies fastened to the sealed deck at the correct 350mm beam.

1. Confirm the deck sealant coat from Phase 2 is fully dry before drilling or screwing into it.
2. Position the two core-rod/noodle assemblies parallel, **350mm beam (centerline to centerline)**, with the deck panel centered between them spanning the gap.
3. Mark 2 pipe-strap positions per rod (near each end of the deck's contact span) on the top of each core rod.
4. Screw one galvanized ½" pipe strap at each marked position, through the sealed plywood deck and around the core rod, into the deck underside. 4 straps total (2 per rod).
5. Confirm both rods are parallel and the deck sits flat and level across them.

> **Check:** No skew — both pontoon assemblies parallel at 350mm beam, deck flat. Because every fastener here is mechanical (screws, straps), this step is fully reversible if something needs adjusting — no cure wait, no irreversible bond.

---

## Phase 5 — Mast Installation (20 min)

**Goal:** Mast mounted vertically at the bow, ready for the transducer.

1. Screw the drilled aluminum L-bracket to the deck at the bow-center position.
2. Mount the ¾" pine dowel mast vertically into/against the L-bracket and secure with wood screws.
3. Check the mast is vertical (use a small spirit level). Adjust the bracket screws if needed.
4. Mount the TCT40-16R transducer bracket at the dowel tip, facing forward (toward the buoys).
5. Run the RX signal coax from the transducer down the mast (zip-tie to the dowel every ~50mm), then along the deck to the cable gland entry point on the enclosure.

> **Note:** Target transducer height is 25–30cm above waterline once assembled and floated — this is unchanged from the original spec and will be confirmed in the float test (Phase 6).

---

## Phase 6 — Float Test and Waterline Verification (30 min)

**Goal:** Confirm actual float depth and trim before mounting electronics.

1. Place the bare hull (no electronics) in a tub or pool. Record:
   - Actual waterline position on each noodle-bundle pontoon
   - Trim (bow/stern level) — add ballast weight to equalize if needed
2. Mark the actual waterline on each pontoon bundle with a permanent marker or tape flag.
3. Measure the actual height of the deck above the waterline (target ≥ 80 mm — enclosure must stay dry in calm conditions).
4. Repeat float test with the electronics enclosure (filled with equivalent dead weight ~400 g) placed on the deck to confirm the loaded waterline and mast height above water (target 25–30cm per spec).
5. Buoyancy sanity check: 6 noodles at 500mm give ≈4.7kg lift at half-submersion vs. a ~2.5kg loaded vehicle weight target — expect ~1.9× safety margin at rest, ~3.7× fully submerged. If the float test doesn't roughly match this, re-check noodle count/lashing before proceeding.

> **Target:** Enclosure bottom ≥ 60 mm above waterline. Deck top ≥ 40 mm above waterline at rest.

---

## Phase 7 — Thruster Mounting (30 min — AFTER stall-current bench test passes)

> **GATE: Do NOT mount thrusters until ESP32 stall-current trip firmware is confirmed working and actual stall current has been bench-measured. A poorly mounted thruster is a rework risk even without structural adhesive — get the bench test done first.**

1. Mark thruster mounting position on each pontoon assembly, near the stern end of the core rod.
2. Fasten the LICHIFIT RF-370 thruster mount per its bracket/clamp hardware onto the core rod (mechanical clamp — no adhesive required; the ½" PVC rod is the mounting spine).
3. Route motor leads along the core rod to the deck, then to a cable gland on the enclosure (seal gland with marine silicone at the enclosure wall).
4. Confirm the mount is snug and the thruster shaft is aligned for straight thrust.
5. No cure wait — mechanical fasteners are ready for water contact immediately after mounting.

---

## Phase 8 — Cable Glands and Enclosure Sealing (1 hr)

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
7. Fasten the enclosure to the deck with 4× stainless M4 bolts + washers through the enclosure's mounting flange/standoffs.

---

## Phase 9 — Final Integration Check (1 hr)

Before first water test with electronics:

- [ ] All gland lock rings torqued; silicone bead applied externally
- [ ] Enclosure lid gasket seated, lid bolts torqued evenly
- [ ] Enclosure bolted to deck with 4× M4 bolts + washers, snug against standoffs
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
| Jun 30 (W6 D2) | Home Depot run — noodles, PVC core rod, deck panel, dowel, hardware | 1 hr |
| Jul 1  (W6 D3) | Cut & prep all components; seal deck (Spar Urethane) | 1 hr (+ same-day dry) |
| Jul 1  (W6 D3) | Lash noodle bundles to core rods; mount rods to deck; mast install | 1.5 hr |
| Jul 2  (W6 D4) | Float test bare hull; verify waterline and mast height | 0.5 hr |
| Jul 4–5 (W6 D6-7) | Cable glands; enclosure load; final integration check | 3 hr |
| Week 7 | Thruster mounting (after stall-current bench test) | 0.5 hr |
| Week 8 | Full dry-land E2E rehearsal on completed hull | — |

**Critical path:** None of the hull steps are time-gated by cure — the only passive wait is the same-day Spar Urethane dry time on the deck (Phase 2), which does not block same-day progress to Phase 3 (noodle lashing can happen while the deck dries). Total build time is ~2 hours of hands-on work, almost entirely completable in a single day.
