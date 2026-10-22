"""Batch art order for the story: writes one prompt file per picture and runs Codex (GPT image)
three at a time. Skips pictures that already exist. Results land next to this file as NAME.png.

    python art/story/order.py            order everything missing
    python art/story/order.py 05 cast_bori   order only these (name prefixes)
"""
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
REF = HERE / "ref.webp"  # Sora turnaround, kept out of git

SORA = """The first attached image is the official character turnaround of Sora, the heroine. Keep her design exactly: lavender-silver short wavy hair, small gold crown with a blue diamond gem, blue ribbon with gold diamond charms on one side, gold diamond earrings, deep blue eyes, white dress with royal-blue panels and gold trim, detached white sleeves with blue-and-gold cuffs, blue tassels ending in gold diamonds, white stockings, blue boots.
The third attached image shows Sora's FACE: keep exactly this face (big round deep-blue eyes, small nose, soft round cheeks, child-like proportions, lavender-silver wavy bob with side ribbon) in every picture.
If a fourth image is attached it is Grandma Bori: keep her EXACTLY like it (old woman about 75, wrinkles, silver bun, rust shawl, olive dress, cream apron).
Make Sora as beautiful, lovely and endearing as possible: soft delicate face, big sparkling eyes, gentle blush, natural relaxed pose (not stiff), beautifully rendered hair and fabric."""

RULES = """ANATOMY MUST BE CORRECT: every character has exactly two arms and two legs, a natural unbroken spine and waist (no twisted or bent-back torso), each clearly attached, natural proportions, five fingers per hand, no extra or merged limbs.
MODESTY: wholesome and family-friendly; underwear is never visible, no view under skirts; camera at eye level or slightly above, never a low angle looking up at a skirt; in action poses the skirt and petticoat stay down over the thighs.
No text, no logo, no watermark, no frame."""

STYLE = """STYLE (match the second attached image exactly): classic 1990s TV anime cel. Clean uniform dark ink outlines, flat colors with exactly one hard-edged shadow tone, no gradients, no texture, simple flat painted background, slightly faded film colors. 16:9 landscape.
AVOID the typical AI-illustration look: no golden backlight or rim light, no sparkles, no glitter particles, no bokeh light orbs, no lens flare, no glow halos, no over-saturated colors, no glossy airbrushed shading, no symmetric centered poster composition. Keep the background simpler and quieter than the characters."""

WORLD = """World: a hand-made garden land whose ground is slowly hardening into toy-like plastic brick (LEGO-like studded bricks), with golden reed marshes, cattails, wooden bridges, old lantern posts. Brick creatures are cute chunky toy-brick goblins (red body, blue head, glowing amber eyes, studs on top), not scary."""

CAST = {
    "bori": "Grandma Bori: a small, round, kind old woman with silver hair in a bun, warm brown shawl, apron with tea stains, a wooden walking stick with a little lantern hanging from it, wise twinkling eyes; she runs the cottage shop.",
    "mulgyeol": "Mulgyeol: an anthropomorphic river otter boat-keeper, chibi-sized, sleek brown fur, sailor scarf in teal, holds a long wooden punting pole, a grumpy-but-kind expression.",
    "jae": "Jae: a boy with short spiky ASH-BLACK hair and amber eyes (must look clearly different from Sora: not lavender hair, not blue eyes), a mysterious child in a long hooded grey cloak whose hem looks like it is turning into grey bricks, pale face, sharp determined eyes, one hand reaching out; a rival, not evil at heart.",
    "simji": "Simji: a tall thin old lamplighter with a long white beard, round spectacles, a long brass lamp-lighting pole, a ring of keys and twelve small lantern charms on his belt.",
    "doran": "Doran: an anthropomorphic mole postman, round glasses, blue postal cap and satchel, carefully holding an old yellowed sealed letter tied with string.",
    "kongal": "Kongal: a cheerful little bakery child with flour on the cheeks, apron, holding a tray of bean buns, happily hugging a small toy-brick goblin like a friend.",
}

ORDERS = {
    "02_lantern": f"{SORA}\nScene: Sora gently touches the crown and the blue gem glows; at the same moment a dark old lantern post beside the marsh path lights up warm gold, and next to it a pile of toy bricks begins to stand up into a little brick goblin. Twilight, fireflies, sense of wonder and a little surprise.",
    "03_ambush": f"{SORA}\nScene: action shot, several cute toy-brick goblins rush at Sora through the golden reeds trying to grab her crown; Sora swings a slim sword in a bright arc, ribbon and hair flowing with motion, determined but graceful expression. Dynamic angle, motion lines, sparks.",
    "04_cottage": f"{SORA}\n{CAST['bori']}\nScene: inside Grandma Bori's warm cottage shop at night: shelves of jars and potions, a kettle steaming on a little stove; Bori leans over the table pouring tea from a teapot into the empty cup in front of Sora; Bori's EYES LOOK DOWN AT THE CUP she is filling (natural, careful pouring, gentle smile). Sora sits at the wooden table with both hands resting near the saucer, waiting, looking up at Bori with curious, slightly shy eyes. Only ONE cup for Sora (the one being filled). Cozy firelight.",
    "05_brick_king": f"{SORA}\nScene: a giant brick king (purple brick body, black brick head with two glowing square eyes, gold studded crown, red cape plate) crumbles into scattered bricks after the battle; behind him a blocked waterway bursts free in sparkling water, revealing a stone cave entrance in the ground. Sora stands in the foreground, breathing hard, looking at the opening. Epic, sunset.",
    "06_cave_rival": f"{SORA}\n{CAST['jae']}\nScene: an underground cave with ancient glowing wall paintings of robed moon-keepers holding a crown under eight moons; Jae appears on a ledge above, cloak swirling, pointing at Sora's crown; Sora stands on the cave floor, startled, looking up with one hand raised to protect the crown (standing, not sitting). Blue cave light, mysterious.",
    "07_water_skip": f"{SORA}\nScene: Sora runs lightly across the surface of a shallow marsh as if skipping like a stone, each footstep making a ring of glowing moonlight ripples; the crown gem glows; the east marsh opens ahead toward a distant village with lights. Joyful, free, wind in hair. Morning light.",
    "08_dark_night": f"{SORA}\n{CAST['jae']}\nScene: night in a small village, all lanterns have gone dark one by one; Jae vanishes into the shadows with a trail of grey brick dust; Sora, alone, has fallen to her knees on the cobblestones under a waning moon, exhausted, reaching after Jae. Melancholy blue night, single faint light on Sora.",
    "09_rise_together": f"{SORA}\n{CAST['mulgyeol']}\n{CAST['simji']}\n{CAST['doran']}\n{CAST['kongal']}\nScene: the villagers and Mulgyeol gather around Sora and help her stand up; Simji relights the first of twelve lanterns, Doran holds out the old letter to her, Kongal smiles; warm golden light returning to the street. Heartwarming, hopeful.",
    "10_jae_turns": f"{SORA}\n{CAST['jae']}\nScene: in a forest turned to grey brick, after their duel Jae kneels as the grey cloak cracks and falls away in brick pieces, revealing an ordinary tearful child underneath; Sora kneels and offers her hand kindly. Soft light breaking through stone trees.",
    "11_final_mold": f"{SORA}\n{CAST['mulgyeol']}\nScene: at the heart of the garden, a colossal crescent-moon-shaped grey brick mold looms in a stormy night sky, pulling the land into rigid brick; Three-quarter view from the side and slightly above (her face visible in profile), Sora stands upright with a straight natural back, both feet planted, and holds the crown in her hands (not on her head) raised high, its gem blazing; behind her, lanterns held by villagers light up one by one, a line of warm lights joining her. Mulgyeol stands beside her with the pole. Epic climax.",
    "12_festival": f"{SORA}\n{CAST['bori']}\n{CAST['mulgyeol']}\n{CAST['kongal']}\nScene: a festival under a huge full moon in the revived garden: paper lanterns, flowing streams, green reeds, villagers dancing; former brick goblins sit like friendly toys helping carry lanterns; Sora (child-like chibi proportions exactly like the reference, crown and ribbon clearly visible) laughs happily in the center holding hands with Kongal, Bori and Mulgyeol nearby. Joyful, warm, ending illustration.",
    "cast_bori": f"{CAST['bori']}\nCharacter design sheet: front view and three-quarter view of the same character side by side, full body, plain light background, consistent with the chibi anime proportions of the attached heroine reference (use it only for art style).",
    "cast_mulgyeol": f"{CAST['mulgyeol']}\nCharacter design sheet: front view and three-quarter view side by side, full body, plain light background, art style matching the attached reference.",
    "cast_jae": f"{CAST['jae']}\nCharacter design sheet: front view and three-quarter view side by side, full body, plain light background, art style matching the attached reference.",
    "cast_simji": f"{CAST['simji']}\nCharacter design sheet: front view and three-quarter view side by side, full body, plain light background, art style matching the attached reference.",
    "cast_doran": f"{CAST['doran']}\nCharacter design sheet: front view and three-quarter view side by side, full body, plain light background, art style matching the attached reference.",
    "cast_kongal": f"{CAST['kongal']}\nCharacter design sheet: front view and three-quarter view side by side, full body, plain light background, art style matching the attached reference.",
    "sora_faces": f"{SORA}\nDialogue portrait sheet: a 3 x 2 grid of bust-up portraits of Sora (head and shoulders, same size and framing in every cell) with six expressions: calm smile, surprised, determined, sad with teary eyes, laughing happily, gently embarrassed with blush. Plain soft light background in every cell, no grid lines.",
}


def prompt_for(name):
    body = ORDERS[name]
    style = STYLE if not name.startswith(("cast_", "sora_faces")) else "STYLE (match the second attached image): classic 1990s TV anime cel, clean uniform ink outlines, flat colors with one hard shadow tone, no gradients, no glow, no sparkles."
    world = WORLD if not name.startswith(("cast_", "sora_faces")) else ""
    return (f"Use your image generation tool to create ONE image and save it as {name}.png in the current directory.\n\n"
            f"{body}\n{world}\n{style}\n{RULES}\nWhen done, reply with only the file path.\n")


def order(name):
    out = HERE / f"{name}.png"
    if out.exists() or (HERE / f"{name}.jpg").exists():
        return f"skip {name}"
    (HERE / f"{name}.txt").write_text(prompt_for(name), encoding="utf-8")
    t0 = time.time()
    with open(HERE / f"{name}.txt", encoding="utf-8") as f:
        subprocess.run(["codex", "exec", "--skip-git-repo-check", "-c", 'windows.sandbox="unelevated"', "--sandbox", "workspace-write",
                        "-i", str(REF), "-i", str(HERE / "style_ref.png"), "-i", str(HERE / "face_ref.png")] + (["-i", str(HERE / "bori_ref.png")] if "bori" in ORDERS[name].lower() else []) + ["-"], cwd=HERE, stdin=f, capture_output=True, text=True, encoding="utf-8", errors="replace", shell=True)
    status = "ok" if out.exists() else "FAILED"
    line = f"{status} {name} {time.time() - t0:.0f}s"
    print(line, flush=True)
    return line


if __name__ == "__main__":
    want = [n for n in ORDERS if not sys.argv[1:] or any(n.startswith(a) for a in sys.argv[1:])]
    with ThreadPoolExecutor(3) as pool:
        list(pool.map(order, want))
    print("done", flush=True)
