import Foundation
import ArcusGeometry

// COMPA: 02 Locks & Security (16). Face-based: the origin is on the face the lock is fixed to (a door's or drawer
// front's outside face for keyed locks, its inside face for surface locks), a along the face, b up it, c out of it; the
// front's material is behind (c from -Front Thickness to 0). Electronic locks are geometry and data only.

extension GroupA {
    static var locks: [ComponentDefinition] {
        [camLockKeyed(), drawerLock(), cabinetDoorLock(), slidingDoorLockRatchet(), magneticLock(), electronicLock(), rfidLock(), combinationLock(),
         keypadLock(), boltLock(), espagnolette(), glassCabinetLock(), childSafetyLock(), wardrobeLock(), centralDrawerLock(), lockingLatch()]
    }

    /// A lock: face-based, with a finish and a cylinder (plug) material, a Front Thickness and the lock tags.
    static func lock(_ name: String, _ sub: String, _ description: String, finish f: ComponentFinish = .satinNickel, category: ComponentCategory = .locks) -> ShapeA {
        var g = faced(name, category, sub, description)
        g.b.material(finish, f)
        g.b.material("Cylinder Material", .brass)
        g.b.length("Front Thickness", inch(0.75), instance: true, group: .placement)
        g.b.tags("lock", "security", "hardware")
        return g
    }

    /// A key cylinder through the front at (a, b): a domed head on the face, the barrel through, a keyway in the plug.
    static func keyCylinder(_ g: inout ShapeA, head: String = "Head Diameter", barrel: String = "Diameter", length: String = "Cylinder Length",
                            at p: (String, String) = (CX.zero, CX.zero), face: String = CX.zero) {
        let f = face
        g.revolve("Cylinder Head", along: 2, center: p, profile: PtsA.turned("(\(head)) / 2", CX.mm(3.2), base: f, [(0, 0), (1, 0), (1, 0.35), (0.93, 0.8), (0.82, 1), (0, 1)]))
        g.cylinder("Barrel", along: 2, center: p, radius: "(\(barrel)) / 2", range: ("\(f) - (\(length))", f))
        g.using("Cylinder Material")
        g.cylinder("Plug", along: 2, center: p, radius: "(\(head)) * 0.3", range: ("\(f) + 0.0031 m", "\(f) + 0.0034 m"))
        let saved = g.levels
        g.levels = [.fine]
        g.box("Keyway", a: ("\(p.0) - 0.0006 m", "\(p.0) + 0.0006 m"), b: ("\(p.1) - (\(head)) * 0.2", "\(p.1) + (\(head)) * 0.2"), c: ("\(f) + 0.0034 m", "\(f) + 0.0036 m"))
        g.levels = saved
        g.using(nil)
    }

    /// The cylinder's hole through the front and the coarse symbol of its head.
    static func cylinderHole(_ g: inout ShapeA, barrel: String = "Diameter", head: String = "Head Diameter", at p: (String, String) = (CX.zero, CX.zero)) {
        g.b.drill("Lock cylinder", x: p.0, y: p.1, diameter: barrel, depth: "Host Thickness", through: true)
        g.b.symbol(.face, [.coarse], .circle(p, "(\(head)) / 2"))
    }

    // MARK: Cam Lock

    static func camLockKeyed() -> ComponentDefinition {
        var g = lock("Cam Lock", "Cam & Cylinder Locks", "Keyed cam lock through the front; the cam turns behind it against the carcass.", finish: .chrome)
        g.b.tags("cam lock", "keyed", "cylinder", "cabinet lock", "drawer lock")
        g.b.aliases("keyed cam lock", "cabinet cam lock", "quarter turn lock", "mailbox lock", "19 mm cam lock", "3/4\" cam lock")
        g.b.length("Diameter", mm(19)); g.b.length("Cylinder Length", mm(20)); g.b.length("Head Diameter", mm(22))
        g.b.length("Cam Length", mm(30)); g.b.length("Cam Width", mm(10)); g.b.length("Cam Thickness", mm(2))
        g.b.angle("Turn", 90)
        g.b.host(ComponentHostKind.fronts, faces: [.front], align: .top, alignments: [.top, .center, .topLeft, .topRight], offsetY: inch(1.5))
        g.b.requires(.hostThickness(min: nil, max: "Cylinder Length - 0.002 m"))
        cylinderHole(&g)
        keyCylinder(&g)
        g.revolve("Nut", along: 2, profile: [("Diameter / 2", "-Front Thickness - 0.003 m"), ("Diameter * 0.68", "-Front Thickness - 0.003 m"), ("Diameter * 0.68", "-Front Thickness"),
                                             ("Diameter / 2", "-Front Thickness")])
        g.prism("Cam", along: 2, profile: PtsA.rounded((CX.zero, "Cam Length / 2 - Cam Width / 2"), "Cam Width", "Cam Length", "Cam Width / 2"),
                range: ("-Cylinder Length - Cam Thickness", "-Cylinder Length"))
        g.b.symbol(.top, [.coarse], .rect(("-Head Diameter / 2", "-Cylinder Length - Cam Thickness"), ("Head Diameter / 2", CX.mm(3.2))))
        for (l, cost) in [(16.0, 3.25), (20, 3.50), (25, 3.75), (30, 4.25)] {
            g.b.type("Cam Lock - \(Int(l)) mm", ["Cylinder Length": mm(l)], cost: cost, model: "CAM-19-\(Int(l))",
                     description: "Keyed cam lock, 19 mm (3/4\") body, \(Int(l)) mm (\(TradeA.inchWord(l))) cylinder, for fronts up to \(Int(l - 2)) mm", isDefault: l == 20)
        }
        return g.build()
    }

    // MARK: Drawer Lock

    static func drawerLock() -> ComponentDefinition {
        var g = lock("Drawer Lock", "Cabinet & Drawer Locks", "Rim deadbolt lock behind a drawer front; the bolt throws up into the rail above.", finish: .brass)
        g.b.material("Body Material", .zinc)
        g.b.tags("drawer lock", "deadbolt", "rim lock", "keyed")
        g.b.aliases("drawer deadbolt", "rim drawer lock", "desk drawer lock", "furniture drawer lock")
        g.b.length("Diameter", mm(16)); g.b.length("Head Diameter", mm(20)); g.b.length("Cylinder Length", mm(22), formula: "Front Thickness + 0.003 m")
        g.b.length("Body Width", mm(40)); g.b.length("Body Height", mm(32)); g.b.length("Body Depth", mm(9)); g.b.length("Throw", mm(6))
        g.b.choice("Mounting Position", ["Top Center", "Top Left", "Top Right"], "Top Center", instance: true, group: .placement)
        g.b.host([.drawerFront], faces: [.front], align: .top, alignments: [.top, .topLeft, .topRight], offsetY: inch(1))
        g.b.requires(.hostThickness(min: CX.mm(15), max: CX.mm(22)))
        cylinderHole(&g)
        keyCylinder(&g)
        let back = "-Front Thickness", bt = "Body Height * 0.3"
        g.using("Body Material")
        g.box("Lock Case", a: ("-Body Width / 2", "Body Width / 2"), b: ("-Body Height + \(bt)", bt), c: ("\(back) - Body Depth", back))
        g.box("Flange", a: ("-Body Width / 2 - 0.008 m", "Body Width / 2 + 0.008 m"), b: ("\(bt) - 0.012 m", bt), c: ("\(back) - 0.0015 m", back))
        g.using(finish)
        g.box("Bolt", a: (CX.mm(-5), CX.mm(5)), b: (bt, "\(bt) + Throw"), c: ("\(back) - Body Depth + 0.001 m", "\(back) - 0.002 m"))
        g.box("Strike Plate", a: (CX.mm(-11), CX.mm(11)), b: ("\(bt) + Throw + 0.003 m", "\(bt) + Throw + 0.0045 m"), c: ("\(back) - Body Depth - 0.004 m", back))
        g.screws("Case Screw", at: [("-Body Width / 2 - 0.004 m", "\(bt) - 0.006 m"), ("Body Width / 2 + 0.004 m", "\(bt) - 0.006 m")], c: "\(back) - 0.0015 m", diameter: CX.mm(5), outward: false)
        g.b.symbol(.face, [.coarse], dashed: true, .rect(("-Body Width / 2", "-Body Height + \(bt)"), ("Body Width / 2", bt)))
        g.b.type("Drawer Lock - 16 mm Cylinder", [:], cost: 6.50, model: "DL-16", description: "Rim drawer deadbolt, 16 mm (5/8\") cylinder, brass face", isDefault: true)
        g.b.type("Drawer Lock - 20 mm Cylinder", ["Diameter": mm(20), "Head Diameter": mm(24), "Body Width": mm(50), "Body Height": mm(38), "Body Depth": mm(11), "Throw": mm(8)],
                 cost: 8.25, model: "DL-20", description: "Heavy rim drawer deadbolt, 20 mm (13/16\") cylinder")
        return g.build()
    }

    // MARK: Cabinet Door Lock and Wardrobe Lock (rim locks)

    /// A rim lock on a door's back: the cylinder `Backset` from the door's closing edge (+a), the case reaching that
    /// edge and the bolt throwing past it into a keeper on the carcass or the other leaf.
    static func rimLock(_ g: inout ShapeA) {
        let back = "-Front Thickness"
        g.using("Body Material")
        g.variant("Mortise", when: false) { g in
            g.box("Lock Case", a: ("-Body Width + Backset", "Backset"), b: ("-Body Height / 2", "Body Height / 2"), c: ("\(back) - Body Depth", back))
            g.box("Bolt", a: ("Backset - 0.002 m", "Backset + Throw"), b: (CX.mm(-6), CX.mm(6)), c: ("\(back) - Body Depth + 0.002 m", "\(back) - 0.002 m"))
            g.using(finish)
            g.box("Keeper", a: ("Backset + Throw + 0.002 m", "Backset + Throw + 0.004 m"), b: (CX.mm(-12), CX.mm(12)), c: ("\(back) - Body Depth - 0.003 m", back))
            g.screws("Case Screw", at: [("-Body Width + Backset + 0.006 m", "Body Height / 2 - 0.006 m"), ("-Body Width + Backset + 0.006 m", "-Body Height / 2 + 0.006 m")],
                     c: "\(back) - Body Depth", diameter: CX.mm(5), outward: false)
        }
        g.variant("Mortise") { g in
            // Let into the door's edge: the case inside the front, a forend plate on the edge.
            g.box("Lock Case", a: ("-Body Width + Backset", "Backset - 0.003 m"), b: ("-Body Height / 2", "Body Height / 2"), c: ("\(back) + 0.003 m", CX.mm(-3)))
            g.using(finish)
            g.box("Forend", a: ("Backset - 0.003 m", "Backset"), b: ("-Body Height / 2 - 0.008 m", "Body Height / 2 + 0.008 m"), c: ("\(back) + 0.002 m", CX.mm(-2)))
            g.box("Bolt", a: ("Backset", "Backset + Throw"), b: (CX.mm(-6), CX.mm(6)), c: ("\(back) / 2 - 0.003 m", "\(back) / 2 + 0.003 m"))
        }
        g.using(nil)
    }

    static func cabinetDoorLock() -> ComponentDefinition {
        var g = lock("Cabinet Door Lock", "Cabinet & Drawer Locks", "Keyed rim or mortise lock for cupboard doors, the bolt into a keeper on the carcass.")
        g.b.material("Body Material", .zinc)
        g.b.tags("door lock", "cupboard lock", "rim lock", "mortise lock", "keyed")
        g.b.aliases("cupboard lock", "cabinet lock", "rim cupboard lock", "mortice lock", "furniture door lock")
        g.b.length("Diameter", mm(16)); g.b.length("Head Diameter", mm(20)); g.b.length("Cylinder Length", mm(22), formula: "Front Thickness + 0.003 m")
        g.b.length("Backset", mm(20)); g.b.length("Body Width", mm(50)); g.b.length("Body Height", mm(40)); g.b.length("Body Depth", mm(10)); g.b.length("Throw", mm(7))
        g.b.choice("Type", ["Rim", "Mortise"], "Rim")
        g.b.flag("Mortise", false, instance: false, group: .dimensions)
        g.b.host([.door], faces: [.front], align: .inside, alignments: [.inside, .center], offsetX: mm(20))
        g.b.requires(.hostThickness(min: CX.mm(15), max: CX.mm(22)))
        cylinderHole(&g)
        keyCylinder(&g)
        rimLock(&g)
        g.b.symbol(.face, [.coarse], dashed: true, .rect(("-Body Width + Backset", "-Body Height / 2"), ("Backset", "Body Height / 2")))
        g.b.type("Cabinet Door Lock - Rim 20 mm Backset", [:], cost: 7.50, model: "CDL-R20", description: "Rim cupboard lock, 20 mm (13/16\") backset, satin nickel", isDefault: true)
        g.b.type("Cabinet Door Lock - Rim 25 mm Backset", ["Backset": mm(25), "Body Width": mm(60)], cost: 8.25, model: "CDL-R25",
                 description: "Rim cupboard lock, 25 mm (1\") backset")
        g.b.type("Cabinet Door Lock - Mortise 25 mm Backset", ["Backset": mm(25), "Body Width": mm(45), "Body Height": mm(32)], flags: ["Mortise": true], texts: ["Type": "Mortise"],
                 cost: 11.50, model: "CDL-M25", description: "Mortise cupboard lock, 25 mm (1\") backset, brass forend")
        return g.build()
    }

    static func wardrobeLock() -> ComponentDefinition {
        var g = lock("Wardrobe Lock", "Cabinet & Drawer Locks", "Wardrobe rim lock with a longer case and bolt, keyed from the front.", finish: .brass)
        g.b.material("Body Material", .zinc)
        g.b.tags("wardrobe lock", "armoire", "rim lock", "keyed", "closet")
        g.b.aliases("armoire lock", "closet lock", "wardrobe door lock", "almirah lock")
        g.b.length("Diameter", mm(18)); g.b.length("Head Diameter", mm(22)); g.b.length("Cylinder Length", mm(25))
        g.b.length("Backset", mm(40)); g.b.length("Body Width", mm(70)); g.b.length("Body Height", mm(50)); g.b.length("Body Depth", mm(12)); g.b.length("Throw", mm(10))
        g.b.flag("Mortise", false, instance: false, group: .dimensions)
        g.b.host([.door], faces: [.front], align: .inside, alignments: [.inside, .center], offsetX: mm(40), offsetY: inch(42))
        g.b.requires(.hostThickness(min: CX.mm(16), max: "Cylinder Length - 0.002 m"))
        cylinderHole(&g)
        keyCylinder(&g)
        rimLock(&g)
        g.b.symbol(.face, [.coarse], dashed: true, .rect(("-Body Width + Backset", "-Body Height / 2"), ("Backset", "Body Height / 2")))
        g.b.type("Wardrobe Lock - 40 mm Backset", [:], cost: 12.50, model: "WL-40", description: "Wardrobe rim lock, 40 mm (1 9/16\") backset, brass", isDefault: true)
        g.b.type("Wardrobe Lock - 50 mm Backset", ["Backset": mm(50), "Body Width": mm(80), "Cylinder Length": mm(30)], cost: 14.25, model: "WL-50",
                 description: "Wardrobe rim lock, 50 mm (2\") backset, 30 mm cylinder")
        return g.build()
    }

    // MARK: Sliding Door Lock (ratchet)

    static func slidingDoorLockRatchet() -> ComponentDefinition {
        var g = lock("Sliding Door Lock - Ratchet", "Sliding Door Locks", "Ratchet lock for overlapping glass sliding doors: the lock on the front door, the toothed bar on the rear one.",
                     finish: .chrome)
        g.b.tags("sliding door lock", "ratchet", "showcase", "glass", "display cabinet")
        g.b.aliases("sliding door lock", "showcase lock", "ratchet lock", "glass sliding door lock", "display case lock")
        g.b.length("Head Diameter", mm(19)); g.b.length("Diameter", mm(12)); g.b.length("Cylinder Length", mm(12))
        g.b.length("Housing Width", mm(30)); g.b.length("Housing Height", mm(46)); g.b.length("Housing Depth", mm(14))
        g.b.length("Bar Length", mm(90)); g.b.length("Door Gap", mm(8)); g.b.length("Glass Thickness", mm(5))
        g.b.choice("Type", ["Ratchet", "Pin"], "Ratchet")
        g.b.host([.glass, .door], faces: [.front], align: .inside, alignments: [.inside], offsetX: mm(30))
        g.b.requires(.hostThickness(min: CX.mm(4), max: CX.mm(6)))
        // The housing clamps the front leaf's edge; the bar lies behind, on the rear leaf, the cylinder pressing into it.
        g.prism("Housing", along: 2, profile: PtsA.rounded((CX.zero, CX.zero), "Housing Width", "Housing Height", CX.mm(5)), range: (CX.zero, "Housing Depth - 0.003 m"))
        keyCylinder(&g, length: "Housing Depth + Glass Thickness + Door Gap - 0.003 m", face: "Housing Depth - 0.003 m")
        g.box("Housing Back", a: ("-Housing Width / 2", "Housing Width / 2"), b: ("-Housing Height / 2", "Housing Height / 2"), c: ("-Glass Thickness - 0.003 m", "-Glass Thickness"))
        g.box("Ratchet Bar", a: ("-Bar Length / 2", "Bar Length / 2"), b: (CX.mm(-6), CX.mm(6)), c: ("-Glass Thickness - Door Gap - 0.004 m", "-Glass Thickness - Door Gap"))
        let saved = g.levels
        g.levels = [.fine]
        for k in 0..<9 {
            let x = -0.4 + 0.1 * Double(k)
            g.box("Tooth \(k + 1)", a: ("Bar Length * \(LX.num(x)) - 0.0015 m", "Bar Length * \(LX.num(x)) + 0.0015 m"), b: (CX.mm(-6), CX.mm(6)),
                  c: ("-Glass Thickness - Door Gap", "-Glass Thickness - Door Gap + 0.0012 m"))
        }
        g.levels = saved
        g.b.symbol(.face, [.coarse], .rect(("-Housing Width / 2", "-Housing Height / 2"), ("Housing Width / 2", "Housing Height / 2")))
        g.b.type("Sliding Door Lock - Ratchet 5 mm Glass", [:], cost: 9.50, model: "SDL-R5", description: "Ratchet lock for 4-6 mm (3/16\"-1/4\") sliding glass doors", isDefault: true)
        g.b.type("Sliding Door Lock - Ratchet 8 mm Glass", ["Glass Thickness": mm(8), "Housing Depth": mm(16)], cost: 10.75, model: "SDL-R8",
                 description: "Ratchet lock for 6-8 mm (1/4\"-5/16\") sliding glass doors")
        return g.build()
    }

    // MARK: Magnetic Lock

    static func magneticLock() -> ComponentDefinition {
        var g = lock("Magnetic Lock", "Concealed Locks", "Concealed magnetic lock: a latch on the door's back and a catch inside, opened by a magnetic key from outside.",
                     finish: .whitePlastic)
        g.b.material("Latch Material", .greyPlastic)
        g.b.tags("magnetic lock", "concealed", "child safety", "invisible", "keyless")
        g.b.aliases("magnetic cabinet lock", "hidden lock", "invisible lock", "magnet lock", "adhesive magnetic lock")
        g.b.number("Holding Force", 150, unit: "N", group: .data)
        g.b.length("Length", mm(60)); g.b.length("Width", mm(25)); g.b.length("Height", mm(22)); g.b.length("Latch Length", mm(30))
        g.b.host([.door, .drawerFront], faces: [.inside], align: .top, alignments: [.top, .topLeft, .topRight], offsetY: mm(10))
        g.b.drill("Latch screw", x: CX.mm(-8), y: CX.mm(-6), diameter: CX.mm(3), depth: CX.mm(10))
        g.b.drill("Latch screw", x: CX.mm(8), y: CX.mm(-6), diameter: CX.mm(3), depth: CX.mm(10))
        g.b.requires(.note("Holds through fronts up to 3/4\"; open with the magnetic key placed on the outside face."))
        // Origin: the door's back face at the latch (c into the cabinet). The latch hooks into the catch above it.
        g.using("Latch Material")
        g.prism("Latch Base", along: 2, profile: PtsA.rounded((CX.zero, CX.mm(-6)), "Width", CX.mm(14), CX.mm(2)), range: (CX.zero, CX.mm(3)))
        g.box("Latch Hook", a: (CX.mm(-5), CX.mm(5)), b: (CX.mm(-4), CX.mm(6)), c: (CX.mm(3), "Latch Length"))
        g.box("Hook Tip", a: (CX.mm(-5), CX.mm(5)), b: (CX.mm(4), CX.mm(9)), c: ("Latch Length - 0.004 m", "Latch Length"))
        g.using(finish)
        g.prism("Catch", along: 1, profile: PtsA.rounded((CX.zero, "Latch Length / 2 + 0.01 m"), "Width", "Length", CX.mm(3)), range: (CX.mm(9), "Height + 0.009 m"))
        g.b.symbol(.face, [.coarse], dashed: true, .rect(("-Width / 2", CX.mm(-13)), ("Width / 2", "Height + 0.009 m")))
        g.b.symbol(.top, [.coarse], .rect(("-Width / 2", CX.zero), ("Width / 2", "Latch Length / 2 + 0.01 m + Length / 2")))
        g.b.type("Magnetic Lock - Standard", [:], cost: 4.50, model: "ML-150", description: "Concealed magnetic lock, 150 N (34 lbf)", isDefault: true)
        g.b.type("Magnetic Lock - Heavy Duty", ["Length": mm(75), "Width": mm(30), "Height": mm(26)], numbers: ["Holding Force": 300], cost: 6.75, model: "ML-300",
                 description: "Concealed magnetic lock, 300 N (67 lbf), for large doors")
        return g.build()
    }

    // MARK: Electronic, RFID and Keypad locks

    /// A battery lock body on the door's back (c into the cabinet) with its strike on the carcass beside it.
    static func lockBody(_ g: inout ShapeA) {
        g.using("Body Material")
        g.prism("Lock Body", along: 2, profile: PtsA.rounded((CX.zero, CX.zero), "Body Width", "Body Height", CX.mm(4)), range: (CX.zero, "Body Depth"))
        g.using(finish)
        g.box("Latch Bolt", a: ("Body Width / 2", "Body Width / 2 + 0.008 m"), b: (CX.mm(-5), CX.mm(5)), c: ("Body Depth * 0.3", "Body Depth * 0.7"))
        g.box("Strike", a: ("Body Width / 2 + 0.009 m", "Body Width / 2 + 0.024 m"), b: (CX.mm(-15), CX.mm(15)), c: (CX.mm(2), "Body Depth"))
        g.b.symbol(.face, [.coarse], dashed: true, .rect(("-Body Width / 2", "-Body Height / 2"), ("Body Width / 2 + 0.024 m", "Body Height / 2")))
        g.b.symbol(.top, [.coarse], .rect(("-Body Width / 2", CX.zero), ("Body Width / 2 + 0.024 m", "Body Depth")))
    }

    static func electronicLock() -> ComponentDefinition {
        var g = lock("Electronic Cabinet Lock", "Electronic Locks", "Battery cabinet lock inside the door, opened by card, fob or phone.", finish: .steel)
        g.b.material("Body Material", .blackPlastic)
        g.b.tags("electronic lock", "smart lock", "battery", "keyless", "locker")
        g.b.aliases("smart cabinet lock", "electronic locker lock", "bluetooth lock", "card lock", "fob lock", "digital cabinet lock")
        g.b.length("Body Width", mm(90)); g.b.length("Body Height", mm(60)); g.b.length("Body Depth", mm(22))
        g.b.choice("Access Type", ["Card", "Key Fob", "Bluetooth"], "Card")
        g.b.text("Battery", "4 x AA")
        g.b.electrical(watts: 0.05, volts: 6, supply: "DC 6 V battery (4 x AA)", cable: "None", connector: "Emergency USB-C")
        g.b.host([.door, .drawerFront], faces: [.inside], align: .inside, alignments: [.inside, .top], offsetX: mm(70))
        for (x, y) in [("-Body Width / 2 + 0.008 m", "Body Height / 2 - 0.008 m"), ("Body Width / 2 - 0.008 m", "-Body Height / 2 + 0.008 m")] {
            g.b.drill("Body screw", x: x, y: y, diameter: CX.mm(3), depth: CX.mm(12))
        }
        lockBody(&g)
        g.using("Cylinder Material")
        g.prism("Reader Window", along: 2, profile: PtsA.rounded((CX.mm(-12), CX.zero), CX.mm(40), CX.mm(30), CX.mm(3)), range: ("Body Depth", "Body Depth + 0.0008 m"))
        g.b.type("Electronic Cabinet Lock - Card", [:], cost: 45.00, model: "ECL-C", description: "Battery cabinet lock, card access, 4 x AA", isDefault: true)
        g.b.type("Electronic Cabinet Lock - Bluetooth", ["Body Width": mm(100), "Body Height": mm(66)], texts: ["Access Type": "Bluetooth"], cost: 69.00, model: "ECL-B",
                 description: "Battery cabinet lock, phone (Bluetooth) access")
        return g.build()
    }

    static func rfidLock() -> ComponentDefinition {
        var g = lock("RFID Cabinet Lock", "Electronic Locks", "Invisible RFID lock inside the door; the reader reads a tag through up to 3/4\" of wood.", finish: .steel)
        g.b.material("Body Material", .greyPlastic)
        g.b.tags("rfid", "invisible lock", "electronic lock", "keyless", "tag")
        g.b.aliases("rfid lock", "invisible cabinet lock", "hidden electronic lock", "nfc cabinet lock", "touch tag lock")
        g.b.length("Body Width", mm(80)); g.b.length("Body Height", mm(45)); g.b.length("Body Depth", mm(18))
        g.b.length("Reader Position", mm(60), instance: true, group: .placement)
        g.b.text("Battery", "3 x AAA")
        g.b.electrical(watts: 0.03, volts: 4.5, supply: "DC 4.5 V battery (3 x AAA)", cable: "None", connector: "Emergency power contacts")
        g.b.host([.door, .drawerFront], faces: [.inside], align: .inside, alignments: [.inside, .top], offsetX: mm(60))
        g.b.requires(.hostThickness(min: nil, max: CX.mm(20)))
        lockBody(&g)
        g.using("Cylinder Material")
        g.cylinder("Reader", along: 2, center: ("-Reader Position + Body Width / 2", CX.zero), radius: CX.mm(12), range: ("Body Depth", "Body Depth + 0.001 m"))
        g.b.type("RFID Cabinet Lock - Standard", [:], cost: 39.00, model: "RFL-S", description: "Invisible RFID cabinet lock, 3 x AAA, reads through 20 mm (3/4\")", isDefault: true)
        g.b.type("RFID Cabinet Lock - Compact", ["Body Width": mm(65), "Body Height": mm(38), "Body Depth": mm(15)], cost: 34.00, model: "RFL-C",
                 description: "Compact invisible RFID cabinet lock")
        return g.build()
    }

    static func keypadLock() -> ComponentDefinition {
        var g = lock("Keypad Lock", "Electronic Locks", "Keypad on the front, lock body inside, joined through a cable hole.", finish: .matteBlack)
        g.b.material("Body Material", .blackPlastic)
        g.b.material("Key Material", .greyPlastic)
        g.b.tags("keypad", "code lock", "pin", "electronic lock", "locker")
        g.b.aliases("keypad cabinet lock", "digital lock", "pin code lock", "code lock", "locker keypad lock", "combination keypad")
        g.b.length("Pad Width", mm(45)); g.b.length("Pad Height", mm(100)); g.b.length("Pad Depth", mm(14))
        g.b.length("Body Width", mm(70)); g.b.length("Body Height", mm(80)); g.b.length("Body Depth", mm(20))
        g.b.choice("Orientation", ["Vertical", "Horizontal"], "Vertical", instance: true, group: .placement)
        g.b.text("Battery", "4 x AAA")
        g.b.electrical(watts: 0.08, volts: 6, supply: "DC 6 V battery (4 x AAA)", cable: "Keypad cable through a 12 mm hole", connector: "4-pin")
        g.b.host([.door, .drawerFront], faces: [.front], align: .inside, alignments: [.inside, .center], offsetX: mm(40), vertical: true)
        g.b.drill("Cable hole", x: CX.zero, y: CX.zero, diameter: CX.mm(12), depth: "Host Thickness", through: true)
        g.b.drill("Pad screw", x: CX.zero, y: "Pad Height / 2 - 0.01 m", diameter: CX.mm(4), depth: "Host Thickness", through: true)
        // The pad on the face; the body behind the front.
        g.prism("Keypad", along: 2, profile: PtsA.rounded((CX.zero, CX.zero), "Pad Width", "Pad Height", CX.mm(6)), range: (CX.zero, "Pad Depth - 0.002 m"))
        g.prism("Keypad Face", along: 2, profile: PtsA.rounded((CX.zero, CX.zero), "Pad Width - 0.003 m", "Pad Height - 0.003 m", CX.mm(5)), range: ("Pad Depth - 0.002 m", "Pad Depth"))
        g.using("Key Material")
        for r in 0..<4 {
            for c in 0..<3 {
                let x = Double(c - 1) * 0.3, y = 0.22 - Double(r) * 0.15
                g.prism("Key \(r * 3 + c + 1)", along: 2, profile: PtsA.rounded(("Pad Width * \(LX.num(x))", "Pad Height * \(LX.num(y))"), "Pad Width * 0.22", "Pad Height * 0.1", CX.mm(1.5)),
                        range: ("Pad Depth", "Pad Depth + 0.0012 m"))
            }
        }
        g.using("Body Material")
        g.box("Lock Body", a: ("-Body Width / 2", "Body Width / 2"), b: ("-Body Height / 2", "Body Height / 2"), c: ("-Front Thickness - Body Depth", "-Front Thickness"))
        g.using(finish)
        g.box("Latch Bolt", a: ("Body Width / 2", "Body Width / 2 + 0.01 m"), b: (CX.mm(-6), CX.mm(6)), c: ("-Front Thickness - Body Depth * 0.7", "-Front Thickness - Body Depth * 0.3"))
        g.b.symbol(.face, [.coarse], .rect(("-Pad Width / 2", "-Pad Height / 2"), ("Pad Width / 2", "Pad Height / 2")))
        g.b.symbol(.top, [.coarse], .rect(("-Pad Width / 2", CX.zero), ("Pad Width / 2", "Pad Depth")))
        g.b.type("Keypad Lock - Standard", [:], cost: 59.00, model: "KPL-S", description: "Keypad cabinet lock, 4 x AAA, 45 x 100 mm (1 3/4\" x 4\") pad", isDefault: true)
        g.b.type("Keypad Lock - Compact", ["Pad Width": mm(38), "Pad Height": mm(80), "Pad Depth": mm(12), "Body Width": mm(60), "Body Height": mm(65)], cost: 49.00, model: "KPL-C",
                 description: "Compact keypad cabinet lock")
        return g.build()
    }

    // MARK: Combination Lock

    static func combinationLock() -> ComponentDefinition {
        var g = lock("Combination Lock", "Cam & Cylinder Locks", "Dial combination cam lock: number wheels in a housing on the face, the cam behind.", finish: .zinc)
        g.b.material("Dial Material", .blackPlastic)
        g.b.tags("combination lock", "dial", "code", "locker", "keyless")
        g.b.aliases("combination cam lock", "dial lock", "locker combination lock", "code cam lock", "number lock")
        g.b.length("Housing Width", mm(32)); g.b.length("Housing Height", mm(70)); g.b.length("Housing Depth", mm(12))
        g.b.length("Dial Diameter", mm(12)); g.b.length("Cylinder Length", mm(20), formula: "Front Thickness + 0.002 m"); g.b.length("Cam Length", mm(35))
        g.b.flag("Four Dials", false, instance: false, group: .dimensions)
        g.b.choice("Mounting", ["Vertical", "Horizontal"], "Vertical", instance: true, group: .placement)
        g.b.host([.door, .drawerFront], faces: [.front], align: .inside, alignments: [.inside, .top], offsetX: mm(30), vertical: true)
        g.b.drill("Spindle hole", x: CX.zero, y: "-Housing Height * 0.3", diameter: CX.mm(19), depth: "Host Thickness", through: true)
        g.b.drill("Housing screw", x: CX.zero, y: "Housing Height * 0.38", diameter: CX.mm(4), depth: "Host Thickness", through: true)
        g.prism("Housing", along: 2, profile: PtsA.rounded((CX.zero, CX.zero), "Housing Width", "Housing Height", CX.mm(6)), range: (CX.zero, "Housing Depth"))
        g.using("Dial Material")
        for (k, y, four) in [(1, 0.22, false), (2, 0.09, false), (3, -0.04, false), (4, -0.17, true)] {
            let body: (inout ShapeA) -> Void = { g in
                g.cylinder("Dial \(k)", along: 0, center: ("Housing Height * \(LX.num(y))", "Housing Depth - Dial Diameter * 0.25"), radius: "Dial Diameter / 2",
                           range: ("-Housing Width * 0.3", "Housing Width * 0.3"), segments: 16)
            }
            if four { g.variant("Four Dials", body) } else { body(&g) }
        }
        g.using(finish)
        g.revolve("Turn Knob", along: 2, center: (CX.zero, "-Housing Height * 0.33"), profile: PtsA.turned(CX.mm(8), CX.mm(9), [(0, 0), (1, 0), (1, 0.7), (0.8, 1), (0, 1)]).map { ($0.0, "Housing Depth + \($0.1)") })
        g.cylinder("Barrel", along: 2, center: (CX.zero, "-Housing Height * 0.3"), radius: CX.mm(9), range: ("-Cylinder Length", CX.zero))
        g.prism("Cam", along: 2, profile: PtsA.rounded((CX.zero, "-Housing Height * 0.3 + Cam Length / 2 - 0.005 m"), CX.mm(10), "Cam Length", CX.mm(5)),
                range: ("-Cylinder Length - 0.002 m", "-Cylinder Length"))
        g.b.symbol(.face, [.coarse], .rect(("-Housing Width / 2", "-Housing Height / 2"), ("Housing Width / 2", "Housing Height / 2")))
        g.b.symbol(.top, [.coarse], .rect(("-Housing Width / 2", "-Cylinder Length"), ("Housing Width / 2", "Housing Depth")))
        g.b.type("Combination Lock - 3 Dial", [:], flags: ["Four Dials": false], cost: 14.50, model: "CBL-3", description: "3-dial combination cam lock, zinc housing", isDefault: true)
        g.b.type("Combination Lock - 4 Dial", ["Housing Height": mm(80)], flags: ["Four Dials": true], cost: 16.75, model: "CBL-4", description: "4-dial combination cam lock")
        return g.build()
    }

    // MARK: Furniture Bolt Lock

    static func boltLock() -> ComponentDefinition {
        var g = lock("Furniture Bolt Lock", "Bolts & Latches", "Barrel (shoot) bolt on a door's back that slides into a keeper on the carcass.", finish: .brass)
        g.b.tags("bolt", "barrel bolt", "slide bolt", "shoot bolt", "door bolt")
        g.b.aliases("barrel bolt", "slide bolt", "tower bolt", "shoot bolt", "cabinet bolt", "flush bolt")
        g.b.length("Length", inch(3)); g.b.length("Plate Width", mm(25)); g.b.length("Bolt Diameter", mm(8)); g.b.length("Throw", mm(15))
        g.b.host([.door], faces: [.inside], align: .top, alignments: [.top, .bottom, .topLeft, .topRight], offsetY: mm(5), vertical: true)
        for y in ["Length * 0.2", "Length * 0.8"] { g.b.drill("Bolt screw", x: CX.zero, y: "-(\(y))", diameter: CX.mm(3), depth: CX.mm(10)) }
        // Origin: the door's top edge on its back face; the bolt runs up (b) and shoots past the edge by Throw.
        g.prism("Back Plate", along: 2, profile: PtsA.rounded((CX.zero, "-Length / 2"), "Plate Width", "Length", CX.mm(3)), range: (CX.zero, CX.mm(1.5)))
        for (n, y0, y1) in [("Guide", "-Length * 0.95", "-Length * 0.6"), ("Guide", "-Length * 0.4", "-Length * 0.05")] {
            g.prism(n, along: 1, profile: PtsA.rounded((CX.zero, "Bolt Diameter / 2 + 0.0015 m"), "Bolt Diameter + 0.004 m", "Bolt Diameter + 0.003 m", CX.mm(2)), range: (y0, y1))
        }
        g.cylinder("Bolt", along: 1, center: (CX.zero, "Bolt Diameter / 2 + 0.0015 m"), radius: "Bolt Diameter / 2", range: ("-Length * 0.92", "Throw"), segments: 20)
        g.cylinder("Bolt Knob", along: 2, center: (CX.zero, "-Length * 0.5"), radius: CX.mm(4), range: ("Bolt Diameter + 0.0015 m", "Bolt Diameter + 0.01 m"), segments: 16)
        g.box("Keeper", a: ("-Bolt Diameter", "Bolt Diameter"), b: ("Throw - 0.006 m", "Throw + 0.003 m"), c: (CX.zero, "Bolt Diameter + 0.004 m"))
        g.b.symbol(.face, [.coarse], .rect(("-Plate Width / 2", "-Length"), ("Plate Width / 2", "Throw")))
        g.b.symbol(.top, [.coarse], .rect(("-Plate Width / 2", CX.zero), ("Plate Width / 2", "Bolt Diameter + 0.004 m")))
        for (l, cost) in [(2.0, 3.25), (3.0, 3.95), (4.0, 4.75)] {
            g.b.type("Furniture Bolt Lock - \(Int(l))\"", ["Length": inch(l), "Throw": inch(l) * 0.2], cost: cost, model: "FBL-\(Int(l))",
                     description: "Barrel bolt, \(Int(l))\" (\(Int(l * 25.4)) mm), brass", isDefault: l == 3)
        }
        return g.build()
    }

    // MARK: Espagnolette Lock

    static func espagnolette() -> ComponentDefinition {
        var g = lock("Espagnolette Lock", "Bolts & Latches", "Multi-point espagnolette: a central gearbox driving rods up and down the door into keepers.", finish: .zinc)
        g.b.material("Rod Material", .steel)
        g.b.tags("espagnolette", "multi point", "rod lock", "wardrobe", "tall door")
        g.b.aliases("espag lock", "multipoint lock", "cremone bolt", "rod lock", "espagnolette bolt", "tall door lock")
        g.b.length("Rod Length", mm(1800)); g.b.integer("Locking Points", 2)
        g.b.length("Gearbox Width", mm(36)); g.b.length("Gearbox Height", mm(120)); g.b.length("Gearbox Depth", mm(12)); g.b.length("Rod Diameter", mm(8))
        g.b.flag("Point 3", false, formula: "Locking Points >= 3")
        g.b.flag("Point 4", false, formula: "Locking Points >= 4")
        g.b.host([.door], faces: [.inside], align: .inside, alignments: [.inside], offsetX: mm(30), vertical: true)
        g.b.drill("Spindle hole", x: CX.zero, y: CX.zero, diameter: CX.mm(10), depth: "Host Thickness", through: true)
        g.b.requires(.fitsHeight("Rod Length + 0.02 m"))
        // Origin: the door's back face at the spindle (mid height), rods along b.
        g.prism("Gearbox", along: 2, profile: PtsA.rounded((CX.zero, CX.zero), "Gearbox Width", "Gearbox Height", CX.mm(4)), range: (CX.zero, "Gearbox Depth"))
        g.using("Rod Material")
        let rc = ("Rod Diameter / 2 + 0.002 m", CX.zero)
        g.cylinder("Upper Rod", along: 1, center: (CX.zero, rc.0), radius: "Rod Diameter / 2", range: ("Gearbox Height / 2", "Rod Length / 2"), segments: 16)
        g.cylinder("Lower Rod", along: 1, center: (CX.zero, rc.0), radius: "Rod Diameter / 2", range: ("-Rod Length / 2", "-Gearbox Height / 2"), segments: 16)
        g.using(finish)
        func point(_ g: inout ShapeA, _ n: String, _ y: String) {
            g.box("\(n) Guide", a: ("-Rod Diameter", "Rod Diameter"), b: ("\(y) - 0.012 m", "\(y) + 0.012 m"), c: (CX.zero, "Rod Diameter + 0.004 m"))
            g.cylinder("\(n) Roller", along: 2, center: ("Rod Diameter + 0.004 m", y), radius: CX.mm(5), range: (CX.mm(2), "Rod Diameter + 0.004 m"), segments: 16)
            g.box("\(n) Keeper", a: ("Rod Diameter + 0.01 m", "Rod Diameter + 0.016 m"), b: ("\(y) - 0.02 m", "\(y) + 0.02 m"), c: (CX.zero, "Rod Diameter + 0.006 m"))
        }
        point(&g, "Top Point", "Rod Length / 2 - 0.02 m")
        point(&g, "Bottom Point", "-Rod Length / 2 + 0.02 m")
        g.variant("Point 3") { g in point(&g, "Upper Middle Point", "Rod Length / 4") }
        g.variant("Point 4") { g in point(&g, "Lower Middle Point", "-Rod Length / 4") }
        g.b.symbol(.face, [.coarse], .line((CX.zero, "-Rod Length / 2"), (CX.zero, "Rod Length / 2")),
                   .rect(("-Gearbox Width / 2", "-Gearbox Height / 2"), ("Gearbox Width / 2", "Gearbox Height / 2")))
        g.b.type("Espagnolette Lock - 1200 mm, 2 Points", ["Rod Length": mm(1200)], cost: 32.00, model: "ESP-1200-2", description: "Espagnolette, 1200 mm (47\") rods, 2 locking points")
        g.b.type("Espagnolette Lock - 1800 mm, 3 Points", [:], numbers: ["Locking Points": 3], cost: 44.00, model: "ESP-1800-3",
                 description: "Espagnolette, 1800 mm (71\") rods, 3 locking points", isDefault: true)
        g.b.type("Espagnolette Lock - 2100 mm, 4 Points", ["Rod Length": mm(2100)], numbers: ["Locking Points": 4], cost: 52.00, model: "ESP-2100-4",
                 description: "Espagnolette, 2100 mm (83\") rods, 4 locking points")
        return g.build()
    }

    // MARK: Glass Cabinet Lock

    static func glassCabinetLock() -> ComponentDefinition {
        var g = lock("Glass Cabinet Lock", "Glass Door Locks", "Clamp-on lock for a glass door's edge: no drilling, the bolt into a keeper on the carcass.", finish: .chrome)
        g.b.tags("glass lock", "showcase", "display cabinet", "clamp", "glass door")
        g.b.aliases("glass door lock", "showcase lock", "display case lock", "clamp glass lock", "frameless glass lock")
        g.b.length("Glass Thickness", mm(5)); g.b.length("Body Width", mm(36)); g.b.length("Body Height", mm(60)); g.b.length("Body Depth", mm(10))
        g.b.length("Head Diameter", mm(18)); g.b.length("Diameter", mm(12)); g.b.length("Throw", mm(8))
        g.b.choice("Type", ["Clamp", "Drilled"], "Clamp")
        g.b.host([.glass, .door], faces: [.front], align: .inside, alignments: [.inside], offsetX: 0)
        g.b.requires(.hostThickness(min: CX.mm(4), max: CX.mm(8)))
        // Origin: the glass edge (closing side, +a is past the edge) at the front face.
        let x0 = "-Body Width", x1 = CX.zero
        g.prism("Front Clamp", along: 2, profile: PtsA.rounded(("-Body Width / 2", CX.zero), "Body Width", "Body Height", CX.mm(4)), range: (CX.zero, "Body Depth"))
        g.box("Back Clamp", a: (x0, x1), b: ("-Body Height / 2", "Body Height / 2"), c: ("-Glass Thickness - 0.004 m", "-Glass Thickness"))
        g.box("Bridge", a: (CX.zero, CX.mm(3)), b: ("-Body Height / 2", "Body Height / 2"), c: ("-Glass Thickness - 0.004 m", "Body Depth"))
        g.box("Bolt", a: (CX.mm(3), "Throw + 0.003 m"), b: (CX.mm(-6), CX.mm(6)), c: (CX.mm(2), "Body Depth - 0.002 m"))
        keyCylinder(&g, length: "Body Depth - 0.002 m", at: ("-Body Width / 2", CX.zero), face: "Body Depth")
        g.screws("Clamp Screw", at: [("-Body Width / 2", "Body Height / 2 - 0.008 m"), ("-Body Width / 2", "-Body Height / 2 + 0.008 m")], c: "Body Depth", diameter: CX.mm(4))
        g.b.symbol(.face, [.coarse], .rect((x0, "-Body Height / 2"), ("Throw + 0.003 m", "Body Height / 2")))
        g.b.symbol(.top, [.coarse], .rect((x0, "-Glass Thickness - 0.004 m"), (CX.mm(3), "Body Depth")))
        g.b.type("Glass Cabinet Lock - 4-6 mm Glass", [:], cost: 11.50, model: "GCL-5", description: "Clamp-on glass door lock for 4-6 mm (3/16\"-1/4\") glass", isDefault: true)
        g.b.type("Glass Cabinet Lock - 6-8 mm Glass", ["Glass Thickness": mm(8), "Body Width": mm(40)], cost: 12.75, model: "GCL-8",
                 description: "Clamp-on glass door lock for 6-8 mm (1/4\"-5/16\") glass")
        return g.build()
    }

    // MARK: Child Safety Lock

    static func childSafetyLock() -> ComponentDefinition {
        var g = lock("Child Safety Lock", "Safety Locks", "Spring latch inside a cabinet door: a flexible hook on the door catches on the carcass until pressed.",
                     finish: .whitePlastic)
        g.b.material("Magnet Material", .steel)
        g.b.tags("child safety", "baby proof", "safety latch", "childproof", "spring latch")
        g.b.aliases("childproof latch", "baby lock", "cabinet safety latch", "safety catch", "toddler lock")
        g.b.length("Arm Length", mm(70)); g.b.length("Arm Width", mm(14)); g.b.length("Catch Width", mm(28))
        g.b.choice("Type", ["Spring Latch", "Magnetic"], "Spring Latch")
        g.b.flag("Magnetic Type", false, instance: false, group: .dimensions)
        g.b.length("Mounting Position", mm(10), instance: true, group: .placement)
        g.b.host([.door, .drawerFront], faces: [.inside], align: .top, alignments: [.top, .topLeft, .topRight], offsetY: mm(10))
        g.b.drill("Latch screw", x: CX.zero, y: CX.mm(-25), diameter: CX.mm(3), depth: CX.mm(10))
        // Origin: the door's back face near its top (c into the cabinet); the catch is on the face frame or top above.
        g.variant("Magnetic Type", when: false) { g in
            g.box("Base", a: ("-Arm Width / 2", "Arm Width / 2"), b: (CX.mm(-35), CX.mm(-15)), c: (CX.zero, CX.mm(4)))
            g.blend("Arm", along: 2, bottom: PtsA.rect((CX.zero, CX.mm(-20)), "Arm Width", CX.mm(6)), top: PtsA.rect((CX.zero, CX.mm(-6)), "Arm Width", CX.mm(4)), range: (CX.mm(4), "Arm Length"))
            g.box("Hook", a: ("-Arm Width / 2", "Arm Width / 2"), b: (CX.mm(-8), CX.mm(2)), c: ("Arm Length - 0.008 m", "Arm Length"))
            g.box("Catch", a: ("-Catch Width / 2", "Catch Width / 2"), b: (CX.mm(4), CX.mm(16)), c: ("Arm Length - 0.02 m", "Arm Length - 0.008 m"))
        }
        g.variant("Magnetic Type") { g in
            g.cylinder("Latch", along: 2, center: (CX.zero, CX.mm(-15)), radius: CX.mm(14), range: (CX.zero, CX.mm(8)))
            g.using("Magnet Material")
            g.cylinder("Catch", along: 2, center: (CX.zero, CX.mm(8)), radius: CX.mm(16), range: (CX.mm(2), CX.mm(14)))
            g.using(nil)
        }
        g.b.symbol(.face, [.coarse], dashed: true, .rect(("-Catch Width / 2", CX.mm(-35)), ("Catch Width / 2", CX.mm(16))))
        g.b.type("Child Safety Lock - Spring Latch", [:], cost: 1.25, model: "CSL-S", description: "Spring safety latch, screw-on, white", isDefault: true)
        g.b.type("Child Safety Lock - Magnetic", [:], flags: ["Magnetic Type": true], texts: ["Type": "Magnetic"], cost: 4.95, model: "CSL-M",
                 description: "Magnetic safety lock, adhesive or screw-on, opened with a magnetic key")
        return g.build()
    }

    // MARK: Central Drawer Lock

    static func centralDrawerLock() -> ComponentDefinition {
        var g = lock("Central Drawer Lock", "Cabinet & Drawer Locks", "One lock in the top drawer front locks every drawer: a rod down the carcass side catches each drawer.",
                     finish: .chrome)
        g.b.material("Rod Material", .steel)
        g.b.tags("central locking", "drawer lock", "pedestal", "file cabinet", "rod lock")
        g.b.aliases("central locking system", "pedestal lock", "filing cabinet lock", "gang lock", "multi drawer lock")
        g.b.length("Rod Length", mm(600)); g.b.integer("Drawer Count", 4)
        g.b.length("Diameter", mm(19)); g.b.length("Head Diameter", mm(22)); g.b.length("Cylinder Length", mm(22), formula: "Front Thickness + 0.003 m")
        g.b.length("Rod Width", mm(16)); g.b.length("Setback", mm(25))
        for k in 2...6 { g.b.flag("Catch \(k)", false, formula: "Drawer Count >= \(k)") }
        g.b.host([.drawerFront], faces: [.front], align: .top, alignments: [.top, .topRight, .topLeft], offsetY: inch(1))
        cylinderHole(&g)
        keyCylinder(&g)
        // The rod runs down from behind the top drawer's front; a catch per drawer at even spacing.
        let rodC = "-Front Thickness - Setback"
        g.using("Rod Material")
        g.box("Rod", a: ("-Rod Width / 2", "Rod Width / 2"), b: ("-Rod Length", CX.mm(10)), c: ("\(rodC) - 0.002 m", rodC))
        g.box("Cam Link", a: (CX.mm(-5), CX.mm(5)), b: (CX.mm(-5), CX.mm(10)), c: (rodC, "-Cylinder Length"))
        g.using(finish)
        g.box("Catch 1", a: ("-Rod Width / 2", "Rod Width / 2 + 0.01 m"), b: (CX.mm(-30), CX.mm(-18)), c: ("\(rodC) - 0.008 m", "\(rodC) - 0.002 m"))
        for k in 2...6 {
            g.variant("Catch \(k)") { g in
                g.box("Catch \(k)", a: ("-Rod Width / 2", "Rod Width / 2 + 0.01 m"), b: ("-Rod Length * \(k - 1) / Drawer Count - 0.03 m", "-Rod Length * \(k - 1) / Drawer Count - 0.018 m"),
                      c: ("\(rodC) - 0.008 m", "\(rodC) - 0.002 m"))
            }
        }
        g.b.symbol(.face, [.coarse], dashed: true, .rect(("-Rod Width / 2", "-Rod Length"), ("Rod Width / 2", CX.mm(10))))
        for (n, l, cost) in [(3, 450.0, 24.00), (4, 600, 28.00), (5, 750, 32.00)] {
            g.b.type("Central Drawer Lock - \(n) Drawers", ["Rod Length": mm(l)], numbers: ["Drawer Count": Double(n)], cost: cost, model: "CDK-\(n)",
                     description: "Central locking for \(n) drawers, \(Int(l)) mm (\(TradeA.inchWord(l))) rod", isDefault: n == 4)
        }
        return g.build()
    }

    // MARK: Locking Latch

    static func lockingLatch() -> ComponentDefinition {
        var g = lock("Locking Latch", "Bolts & Latches", "Lockable toggle (draw) latch for lids and cases, with a padlock eye.", finish: .stainless)
        g.b.tags("latch", "toggle latch", "draw latch", "case latch", "padlock")
        g.b.aliases("toggle latch", "draw latch", "case catch", "chest latch", "lockable latch", "hasp latch")
        g.b.length("Length", mm(70)); g.b.length("Width", mm(30)); g.b.length("Height", mm(12)); g.b.length("Keeper Length", mm(20))
        g.b.choice("Orientation", ["Vertical", "Horizontal"], "Vertical", instance: true, group: .placement)
        g.b.host([.sidePanel, .door, .lid], faces: [.front, .outside, .left, .right], align: .top, alignments: [.top, .center], offsetY: inch(0.5))
        for y in ["-Length * 0.8", "-Length * 0.3", "Keeper Length * 0.5"] { g.b.drill("Latch screw", x: CX.zero, y: y, diameter: CX.mm(3.5), depth: CX.mm(12)) }
        // Origin: the joint between body and lid (b up); the latch below it, the keeper above.
        g.prism("Base Plate", along: 2, profile: PtsA.rounded((CX.zero, "-Length / 2"), "Width", "Length", CX.mm(3)), range: (CX.zero, CX.mm(1.5)))
        g.prism("Lever", along: 2, profile: PtsA.rounded((CX.zero, "-Length * 0.45"), "Width * 0.8", "Length * 0.8", CX.mm(4)), range: (CX.mm(1.5), "Height"))
        g.box("Hook", a: ("-Width * 0.3", "Width * 0.3"), b: ("-0.004 m", "Keeper Length * 0.6"), c: ("Height - 0.004 m", "Height - 0.002 m"))
        g.prism("Keeper", along: 2, profile: PtsA.rounded((CX.zero, "Keeper Length / 2"), "Width", "Keeper Length", CX.mm(3)), range: (CX.zero, CX.mm(1.5)))
        g.box("Keeper Lip", a: ("-Width * 0.35", "Width * 0.35"), b: ("Keeper Length * 0.55", "Keeper Length * 0.7"), c: (CX.mm(1.5), "Height - 0.002 m"))
        g.prism("Padlock Eye", along: 1, profile: PtsA.rounded(("Width * 0.5 + 0.003 m", "Height * 0.6"), CX.mm(8), "Height * 0.8", CX.mm(3)),
                range: ("-Length * 0.2", "-Length * 0.2 + 0.003 m"))
        g.b.symbol(.face, [.coarse], .rect(("-Width / 2", "-Length"), ("Width / 2", "Keeper Length")))
        g.b.symbol(.top, [.coarse], .rect(("-Width / 2", CX.zero), ("Width / 2", "Height")))
        g.b.type("Locking Latch - 70 mm", [:], cost: 6.25, model: "LLT-70", description: "Lockable toggle latch, 70 mm (2 3/4\"), stainless", isDefault: true)
        g.b.type("Locking Latch - 100 mm", ["Length": mm(100), "Width": mm(38), "Height": mm(16), "Keeper Length": mm(26)], cost: 8.95, model: "LLT-100",
                 description: "Lockable toggle latch, 100 mm (4\"), stainless")
        return g.build()
    }
}
