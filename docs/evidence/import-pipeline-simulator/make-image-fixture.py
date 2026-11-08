from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

p = Path(__file__).parent / "screenshots"
img = Image.new("RGB", (1200, 1600), "white")
d = ImageDraw.Draw(img)

def font(size, bold=False):
    name = "Arial Bold.ttf" if bold else "Arial.ttf"
    return ImageFont.truetype(f"/System/Library/Fonts/Supplemental/{name}", size)

d.text((80, 90), "Morning Study Plan", font=font(76, True), fill="black")
lines = ["Read one short article every day.", "The quiet library helps students focus."]
y = 250
for line in lines:
    d.text((80, y), line, font=font(42), fill="black")
    y += 82
for line in ["- Open the notebook", "- Choose three words"]:
    d.text((100, y), line, font=font(42), fill="black")
    y += 80
x0, y0, w, h = 100, y + 60, 500, 130
rows = [["Word", "Meaning"], ["library", "a quiet place"]]
for r in range(3):
    d.line((x0, y0 + r * h, x0 + 2 * w, y0 + r * h), fill="black", width=5)
for c in range(3):
    d.line((x0 + c * w, y0, x0 + c * w, y0 + 2 * h), fill="black", width=5)
for r in range(2):
    for c in range(2):
        d.text((x0 + c * w + 30, y0 + r * h + 42), rows[r][c], font=font(38, r == 0), fill="black")
img.save(p / "deterministic-image-import-fixture.png", dpi=(144, 144))
