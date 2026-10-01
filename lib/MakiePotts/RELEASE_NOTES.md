# MakiePotts 0.3.0-rc2

- `renderframe` now accepts explicit typed site, cell, and medium channels from
  saved states and retained solutions.
- Site channels use the same full-domain or orthogonal-slice projection as
  ownership, while cell and medium channels retain their semantic keys.
- Saved-state channel conversion is failure-atomic, validates through the
  canonical frame constructor, and defensively owns every returned frame.

# MakiePotts 0.3.0-rc1

- Tracks the Potts 0.3 package identity and preserves the MakiePotts UUID.
- Owns rendering recipes, visual references, backend tests, examples, and documentation.
- Uses Potts only through its public observation and inspection interfaces.
