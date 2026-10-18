# Fill pattern text format

Arcus fill patterns are sets of **line families**. Manage ▸ Additional Settings ▸ Fill Patterns edits them as
text, and Import…/Export… read and write plain-text files in this format (any extension; `.pat` by convention).
The format is Arcus's own; it uses the common "one line family per line" convention so hand-written pattern files
are easy to read and share.

```
;%UNITS=MM                       units for every number in the file: MM (default) or INCH
*Concrete, cast-in-place         a pattern: *Name[, description]
;%TYPE=DRAFTING                  DRAFTING (default) or MODEL — applies to the pattern above
50,   0, 0,  4.12, 5.9,  0.75, -8.3, 0, -6.6
355,  0, 0,  4.3,  6.1,  0.6,  -7.9, 0, -5.5
100.4, 0.6, 0, 3.7, 5.3, 0.7,  -9.1, 0, -7.2
46,   0, 0,  3.3,  4.7,  0,    -6.1
```

Each line family is `angle, x, y, shift, spacing[, dash, dash, …]`:

| Field   | Meaning |
|---------|---------|
| angle   | Direction of the lines, degrees counter-clockwise from +X. |
| x, y    | A point every line of the family passes through (the pattern origin is the view origin, so hatches never swim). |
| shift   | Offset along the line between successive parallel lines (staggers dashes; 0 keeps them aligned). |
| spacing | Perpendicular distance between successive lines (> 0). |
| dashes  | Optional: positive = pen down, negative = gap, 0 = a dot. No dashes = continuous line. |

Lengths are millimetres: **paper** millimetres for drafting patterns (the same on every sheet whatever the view
scale), **model** millimetres for model patterns (real sizes that scale with the view). Lines starting with `;`
are comments except `;%` directives; blank lines are ignored.

Drafting patterns are what section and plan cuts use (concrete, brick, block, insulation, steel…); model patterns
draw surfaces (brick coursing, tile modules, ceiling grids, boarding). The built-in library (`FillPatternLibrary`)
ships 80+ of both; Add Standard Patterns adds any a project is missing.
