# MVD Transporte - App Icon Setup

## 🎨 Icon Design Concept

**Minimalist design featuring:**
- 🚌 Bus icon (simple silhouette)
- 🛡️ Escudo de Montevideo (coat of arms)
- Clean, modern look
- Blue color scheme (#0066CC)

## 📐 Icon Requirements

- **Format:** PNG (with transparent background preferred)
- **Size:** 1024x1024 pixels (recommended)
- **Minimum:** 512x512 pixels
- **Aspect Ratio:** 1:1 (square)
- **File name:** `app_icon.png` (must be exactly this name)
- **Location:** Place in this `assets/` folder

## 🎨 Design Guidelines

### Color Palette
- **Primary Blue:** #0066CC
- **Secondary Blue:** #0099FF
- **White:** #FFFFFF
- **Gray:** #666666 (for details)

### Design Elements

1. **Bus Icon:**
   - Simple, minimalist bus silhouette
   - Front or side view
   - Clean lines, no excessive detail

2. **Escudo de Montevideo:**
   - Stylized coat of arms
   - Can be simplified for clarity
   - Reference: [Escudo de Montevideo](https://es.wikipedia.org/wiki/Escudo_de_Montevideo)

3. **Layout:**
   - Center the main icon (bus)
   - Add coat of arms as subtle element (corner or integrated)
   - Maintain clean, professional appearance
   - Ensure visibility at small sizes (48x48px)

## 🛠️ Creating the Icon

### Option 1: Use Design Tools

**Figma / Canva / Inkscape:**
1. Create 1024x1024px canvas
2. Add bus icon (simple vector shape)
3. Add Montevideo coat of arms
4. Use #0066CC blue background or white background
5. Export as PNG

### Option 2: Online Icon Generators

**Flaticon / Icons8:**
1. Search for "bus icon" and "montevideo coat of arms"
2. Combine elements in image editor
3. Resize to 1024x1024px
4. Save as `app_icon.png`

### Option 3: AI Image Generation

Use DALL-E, Midjourney, or similar:
```
Prompt: "minimalist app icon, blue bus silhouette with Montevideo
coat of arms, clean design, blue and white colors, 1024x1024px"
```

## ⚡ Quick Test with Placeholder

You can use a temporary icon:
1. Find any bus icon PNG online
2. Resize to 512x512+ pixels
3. Name it `app_icon.png`
4. Place in this folder
5. Replace with final design later

## 🚀 Once Icon is Ready

After saving your icon as `app_icon.png` in this folder:

```bash
cd /Users/undermind/Documents/liberonvpn/MiSTM_pre_alpha_v0/stm_app
flutter pub get
dart run flutter_launcher_icons
flutter clean
flutter build apk --release
```

## 📚 Resources

- **Escudo de Montevideo:** https://commons.wikimedia.org/wiki/File:Coat_of_arms_of_Montevideo.svg
- **Free Icons:** https://www.flaticon.com/search?word=bus
- **Icon Generators:** https://www.canva.com/create/app-icons/
- **Color Picker:** Use #0066CC for primary blue

---

**Note:** This is an unofficial app. The design should be unique and not copy
any official branding from government agencies or transport companies.
