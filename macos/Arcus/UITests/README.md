# UI and end-to-end QA

Arcus's end-to-end checks run inside the real app through the built-in QA harness (`Arcus/UI/Shell/QAHarness.swift`). They don't use XCUITest, so they need no Xcode project, no test host and no Accessibility permission. The harness drives the same `DocumentState`, tools, command router, `DocumentSession` and exporters that the UI uses, then reads the results back from the model and the rendered display lists.

```bash
script/build_and_run.sh --no-launch        # build/Arcus.app
script/qa_capture.sh all build/qa          # workflow + screenshots
script/qa_capture.sh workflow build/qa     # workflow only
script/qa_capture.sh screenshots build/qa  # screenshots only
script/qa_capture.sh interact build/qa     # canvas interaction checks only
```

The script launches `Arcus --skip-onboarding --no-hub --qa <scenario> --qa-out <dir> --qa-quit`. The harness writes `<dir>/results.json`, with pass/fail, detail and duration for each step plus signpost timings. It announces each window state on stdout as `QA-CAPTURE <windowNumber> <name>`, and the script captures that window with `screencapture -l`. Screenshots captured by the script need Screen Recording permission for the **terminal** running it, not for Arcus. The harness also saves an in-process rendering of each window (`*-inprocess.png`), which needs no permission.

## Workflow scenario (`--qa workflow`)

Each step fails with a message if its check fails:

1. Create a project from the Architectural template
2. Draw a rectangle of walls in plan (corners join)
3. Place a hosted door and window (openings cut the host; tags are placed)
4. Floor from picked walls in sketch mode (area checked)
5. Room, column, component, and a stair with railings (room area checked)
6. Beam and grid
7. Roof by footprint on Level 2, and a ceiling in the RCP
8. Add a level from an elevation (a plan and RCP are created)
9. Instance and type parameter edits, with undo and redo verified numerically
10. Dimension, Tag All, text and a revision cloud (measured length checked)
11. Keyboard element stepping (`]` / `[`) and the canvas's VoiceOver custom actions
12. Section view generated from the model (cut walls present)
13. Door and room schedules update live
14. Sheet with plan and schedule viewports
15. Vector PDF export of every sheet (no raster pages)
16. IFC4 and IFC2x3 export, then a round-trip import into a fresh project
17. Schedule CSV and view DXF export
18. Link a DXF, reload it, and convert it to detail lines (the source file's bytes are unchanged)
19. DWG import reports its licensing status truthfully (no fake DWG support)
20. Save, close and reopen (element count and schema version checked)
21. File ▸ Open Recent lists the project
22. 3D coordination view (triangle count checked)

## Screenshots scenario (`--qa screenshots`)

Opens the Courtyard House reference project in light and then dark appearance and captures:

- onboarding and the project hub
- a plan at minimum (980 × 640) and spacious window sizes
- a selected wall with Properties, at minimum and spacious sizes
- sketch mode (floor boundary) and the wall tool with temporary dimensions
- a schedule, a sheet, a section, an elevation and the 3D view
- the IFC export, DWG unavailable, Model Health, PDF export, Visibility/Graphics, Materials, Keyboard Shortcuts, Project Units and Schedule Properties dialogs
- Command Search and an error toast

It then measures 3D frame times on the Courtyard House, opens the 20,000-element stress model (plan build time, 3D frame times and memory), and finally checks that every closed document has released its project data.

The crash-recovery prompt is verified separately: quit Arcus with unsaved changes by force (for example `kill -9`), then relaunch without `--qa`.

## Interaction scenario (`--qa interact`)

Drives the real canvas the way a user does. Mouse, scroll and keyboard events go through the document window, so hit testing, the responder chain, typed aliases and tools all run as they would for a user. After each user action, a posted event lets AppKit finish the event (closing its undo group).

After every action the canvas is verified:

1. **No open undo group** once the event loop is idle (each action is one undo step).
2. **Current:** the display list on screen was built from the current model revision.
3. **Complete:** it contains exactly the elements a fresh build of the view contains (no stale or missing elements).
4. **Drawn:** every element the display list places in the visible area has ink on screen. Pixels are sampled along its strokes and compared with the canvas background. This catches culling, stale bounds, masking and overlay bugs where elements vanish.

Actions covered:
- Drawing walls with the Wall tool (typed `WA`, clicks, Esc); hover preselection; zoom region.
- Click-select and drag-move with undo and redo; pan with trackpad scroll; zoom with the wheel; window select, Delete and undo.
- Door and window placement; room; aligned dimension; text; tag.
- Grid, model line, detail line, structural column, component, beam, stair, room separator.
- Floor and roof sketches (Enter to finish), a ceiling sketch in the RCP, and an elevation marker.
- The Move tool (joined walls follow); Copy; grip drag; copy and paste; zoom region; thin lines.
- Switching views (plan, 3D, elevation), resizing the window and toggling panels.
- Temporary hide and isolate, and reset; light and dark appearance.
- Section tool and section view; a sheet with pan, zoom and viewport double-click.
- Schedule cell editing, checked against the model and the plan tag; 3D orbit and click-select.
- Undo everything, then redo everything.
- In the Courtyard House: plan zoom, pan, hover and click; sheets A101, A201 and A301; every section, elevation and RCP.

Failures are reported with the canvas image saved to `<out>/interact/`.
