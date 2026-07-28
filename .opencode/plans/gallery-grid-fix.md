# Gallery Grid Fix — Implementation

## Changes in `team2`

### 1. GALLERY_HTML — `.detection-grid` CSS (responsive columns)

Replace:

```css
.detection-grid {
  display: grid;
  grid-template-columns: repeat(10, 1fr);
  gap: 10px;
}
.gallery {
  display: grid;
  grid-template-columns: repeat(10, 1fr);
  gap: 12px;
}
```

With:

```css
.detection-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
  gap: 10px;
}
```

### 2. GALLERY_HTML — `.card img` height

Line 1046: `height: 150px;` → `height: 200px;`

### 3. GALLERY_HTML — remove `.gallery` wrapper div

Line 1112: `<div class="gallery">%(cards)s</div>` → `%(cards)s`

## Tests to verify

```bash
bash run-pi-tests.sh --static && tests/pi_deployment/test_team2.sh
timeout 30 python3 /tmp/test_web_gallery.py
```

## Docs to update

- `PLAN.md` — add What Changed entry
- `TEST.md` — update gallery grid test description
