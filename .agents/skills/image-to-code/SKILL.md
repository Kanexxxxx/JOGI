---
name: image-to-code
description: >
  Image-first visual analysis and implementation skill (from Leonxlnx/taste-skill).
  Extracts exact typography, spacing, color tokens, and layout structure from reference
  images or generated concepts before implementing UI or HUD components.
---

# Image-to-Code Visual Extraction Skill

Origin: `https://github.com/Leonxlnx/taste-skill` (`skills/image-to-code-skill/SKILL.md`).

## Workflow

1. **Reference / Concept First:** When implementing a visually critical screen, HUD overlay, or character card from a visual reference (or generated via `image-generator` subagent), treat the image as a strict design specification.
2. **Deep Visual Extraction Before Coding:**
   - Extract exact text hierarchy, font weight contrasts, and alignment.
   - Extract spacing ratios, padding, border radii, and stroke treatments.
   - Extract primary ground, surface, text, and accent color hex values.
   - Avoid nested cards-inside-cards and unnecessary UI chrome.
3. **Section-by-Section Clarity:** Prefer large, readable section references over compressed collages.
