// Builds style_noche.json from @protomaps/basemaps + flavor_noche.json.
// Usage: node gen_style.mjs <basemaps dist/esm/index.js> <style-spec dist/index.mjs> <flavor.json> <out style.json>
// The style is written minified: the app bundles it as it is (assets/map/README.md).
import { readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const [basemapsPath, specPath, flavorPath, outPath] = process.argv.slice(2);
const { layers } = await import(pathToFileURL(basemapsPath).href);
const { validateStyleMin } = await import(pathToFileURL(specPath).href);

const flavor = JSON.parse(readFileSync(flavorPath, "utf8"));
let ls = layers("protomaps", flavor, { lang: "es" });

// No sprite in this style: drop what can only draw sprite icons.
const removed = [];
ls = ls.filter((l) => {
  if (l.id === "roads_oneway" || l.id === "roads_shields") {
    removed.push(l.id);
    return false;
  }
  return true;
});
const strippedIcons = [];
for (const l of ls) {
  if (l.layout && "icon-image" in l.layout) {
    delete l.layout["icon-image"];
    delete l.layout["icon-size"];
    strippedIcons.push(l.id);
  }
}

const style = {
  version: 8,
  name: "Timbre Noche",
  metadata: {
    "timbre:flavor": "flavor_noche.json",
    "timbre:generator": "@protomaps/basemaps 5.7.2 layers('protomaps', flavor, {lang: 'es'})",
    "timbre:removed_layers": removed,
    "timbre:stripped_icon_image": strippedIcons,
  },
  // No `glyphs`: flutter_map_vector_tiles draws labels with Flutter's text
  // engine and never reads it, and the style validates without it.
  sources: {
    protomaps: {
      type: "vector",
      // The app serves this source from its own copy of the archive, by id,
      // and never reads the URL (lib/services/map/basemap.dart).
      url: "pmtiles://__PMTILES__",
      attribution: "© OpenStreetMap",
    },
  },
  layers: ls,
};

// Validation needs a real-looking URL; the placeholder is restored after.
const probe = JSON.parse(
  JSON.stringify(style)
    .replace("pmtiles://__PMTILES__", "pmtiles://https://example.invalid/mvd.pmtiles"),
);
const errors = validateStyleMin(probe);

// Collect font stacks and colours referenced anywhere in the layers.
const fonts = new Set();
const colours = new Set();
const walk = (v, key) => {
  if (typeof v === "string") {
    if (/^#[0-9a-fA-F]{3,8}$/.test(v) || /^rgba?\(/.test(v)) colours.add(v.toUpperCase());
    return;
  }
  if (Array.isArray(v)) {
    if (key === "text-font" || key === "font") {
      // literal stacks: ["Noto Sans Regular"] or ["literal", [...]] inside expressions
      if (v.every((x) => typeof x === "string") && v[0] !== "literal" && v[0] !== "case") fonts.add(v.join(","));
    }
    if (v[0] === "literal" && Array.isArray(v[1]) && v[1].every((x) => typeof x === "string") && key !== "filter") {
      if (v[1].some((x) => /Noto|Sans|Serif/.test(x))) fonts.add(v[1].join(","));
    }
    v.forEach((x) => walk(x, key));
    return;
  }
  if (v && typeof v === "object") {
    for (const [k, x] of Object.entries(v)) {
      if (k === "text-font" || k === "text-font-override" || k === "text-font") walk(x, "text-font");
      else if (k === "text-field") walk(x, "text-field");
      else walk(x, k);
    }
  }
};
walk(ls);
// format expressions carry {"text-font": [...]} objects inside text-field
const raw = JSON.stringify(ls);
for (const m of raw.matchAll(/"text-font":\["literal",\[([^\]]*)\]\]/g)) fonts.add(JSON.parse(`[${m[1]}]`).join(","));

writeFileSync(outPath, JSON.stringify(style) + "\n");
console.log(
  JSON.stringify(
    {
      layers: ls.length,
      removed,
      strippedIcons,
      validationErrors: errors.map((e) => e.message),
      fonts: [...fonts].sort(),
      colours: [...colours].sort(),
      iconRefs: (raw.match(/icon-image/g) || []).length,
    },
    null,
    1,
  ),
);
