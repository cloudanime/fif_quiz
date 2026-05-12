import os
import subprocess
import sys

def install(package):
    subprocess.check_call([sys.executable, "-m", "pip", "install", package])

import numpy as np
from PIL import Image, ImageDraw, ImageFont

def install(package):
    subprocess.check_call([sys.executable, "-m", "pip", "install", package])

try:
    from moviepy import ImageClip, CompositeVideoClip, ColorClip, concatenate_videoclips
except ImportError:
    print("Installing moviepy...")
    install('moviepy')
    from moviepy import ImageClip, CompositeVideoClip, ColorClip, concatenate_videoclips

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("Installing Pillow...")
    install('Pillow')
    from PIL import Image, ImageDraw, ImageFont

def _create_text_image(text, width, height, fontsize, color, bg_color=(253, 239, 255, 0), font_path=None, bold=False):
    # Create an image with transparency
    img = Image.new('RGBA', (width, height), bg_color)
    draw = ImageDraw.Draw(img)
    
    # Try to load a font
    try:
        if font_path:
            font = ImageFont.truetype(font_path, fontsize)
        else:
            # Try some common fonts
            font_names = ["arial.ttf", "DejaVuSans.ttf", "LiberationSans-Regular.ttf"]
            font = None
            for name in font_names:
                try:
                    font = ImageFont.truetype(name, fontsize)
                    break
                except: continue
            if font is None: font = ImageFont.load_default()
    except:
        font = ImageFont.load_default()

    # Wrap text
    lines = []
    words = text.split()
    current_line = []
    for word in words:
        test_line = ' '.join(current_line + [word])
        # Use draw.textbbox if available (Pillow 10+)
        if hasattr(draw, 'textbbox'):
            w = draw.textbbox((0, 0), test_line, font=font)[2]
        else:
            w = draw.textsize(test_line, font=font)[0]
            
        if w <= width:
            current_line.append(word)
        else:
            lines.append(' '.join(current_line))
            current_line = [word]
    lines.append(' '.join(current_line))

    # Draw lines
    y_text = 0
    for line in lines:
        if hasattr(draw, 'textbbox'):
            line_w, line_h = draw.textbbox((0, 0), line, font=font)[2:]
        else:
            line_w, line_h = draw.textsize(line, font=font)
        
        draw.text((0, y_text), line, font=font, fill=color)
        y_text += line_h + 5
        
    return img

def create_manual_video(image_folder, output_name="app_user_guide.mp4"):
    # Theme Colors (RGB)
    PURPLE = (69, 14, 78)
    YELLOW = (255, 214, 0)
    LIGHT_PINK = (253, 239, 255)
    WHITE = (255, 255, 255)
    
    # Video Settings
    W, H = 1920, 1080
    FPS = 24
    SLIDE_DURATION = 5 # seconds
    
    # List of images and their descriptions
    slides_data = [
        ("0 Instructions.png", "Guidance on playing different Game versions, which include:\n- Offline Single Player\n- Offline Multiple Players\n- Online Single Player\n- Online Individual Challenge\n- Online Team Challenge"),
        ("1 Legacy Continues.png", "Message from Visionary and Founder, Archbishop Professor Ezekiel H. Guti."),
        ("3 Offline Game.png", "Offline Game: Synchronize your local database by clicking any of the 2 buttons below. Once done you do not need internet connection to enjoy the game, just start the game."),
        ("4 Adding Players.png", "Renaming players is optional. Each game has a randomly selected 100 questions from our database. You determine how many questions will be played for your game session."),
        ("5 Offline Quiz Grid.png", "Quiz Grid: Scoreboard is located at the bottom of the questions grid. You can change the grid's width, height or font size by using the sliders above."),
        ("6 Mulitple Choice Questions.png", "Multiple Choice: Select the correct answer from the options provided. Immediate feedback will be shown in solo mode."),
        ("7 Marking Answers.png", "Marking Answers: Correct answer and source of the answer is highlighted for your further reading. If Managed by Quiz Master or if marking requires manual marking, use the grid below to mark participants' answers."),
        ("8 Picture Based Questions.png", "Picture Questions: Identify key historical figures, events, or artifacts. These can include book images from our official library."),
        ("9 Open or Structured Questions.png", "Structured Questions: Answer open-ended questions based on deep study of the Legacy materials."),
        ("questions grid.png", "Navigation: Questions that have been attempted will not be available for selections, the flip side of such questions will be shown on the grid. Questions are randomly selected from the grid by the player or Quiz Master."),
        ("11 Online (Quiz Master).png", "Online Hosting: The interface for the Quiz Master to manage live online sessions and track global progress."),
        ("12 Winner.png", "Victory: The celebratory reveal of the final standings and trophy distribution."),
        ("winner review.png", "Grand Review: A look at the final leaderboard and celebratory victory animation."),
        ("create team challenge.png", "Team Challenge: Create a group-based competition. This mode allows for large-scale event participation with multiple teams."),
        ("JoiningTeamChallenge.png", "Joining Teams: Players can enter their specific team code to join their designated group for the challenge."),
        ("team joining.png", "Team Lobby: Watch as your teammates join the session in real-time before the start."),
        ("13 Log in.png", "Authentication: Securely log in to access cloud-synced game features."),
        ("15 Register.png", "Registration: Join the Legacy Quiz community and start hosting your own sessions."),
    ]

    clips = []
    
    print("Generating Grand Video Guide...")

    # Title Slide
    bg = ColorClip(size=(W, H), color=LIGHT_PINK).with_duration(4)
    
    title_img = _create_text_image("LEGACY QUIZ", W, 200, 120, PURPLE)
    title = ImageClip(np.array(title_img)).with_position('center').with_duration(4)
    
    sub_img = _create_text_image("Official User Guide & Documentation", W, 100, 60, (0,0,0))
    subtitle = ImageClip(np.array(sub_img)).with_position(('center', H*0.6)).with_duration(4)
    
    foot_img = _create_text_image("Celebrating 100 Years of God's Grace", W, 80, 40, PURPLE)
    footer = ImageClip(np.array(foot_img)).with_position(('center', H*0.8)).with_duration(4)
    
    clips.append(CompositeVideoClip([bg, title, subtitle, footer]))

    for img_name, description in slides_data:
        img_path = os.path.join(image_folder, img_name)
        if not os.path.exists(img_path):
            print(f"Warning: {img_path} not found. Skipping.")
            continue
            
        bg = ColorClip(size=(W, H), color=LIGHT_PINK).with_duration(SLIDE_DURATION)
        
        img_clip = ImageClip(img_path).with_duration(SLIDE_DURATION)
        # In 2.x resize might be resized()
        try:
            img_clip = img_clip.resized(height=int(H*0.8))
        except AttributeError:
            img_clip = img_clip.resize(height=int(H*0.8))
            
        img_clip = img_clip.with_position((int(W*0.05), 'center'))
        
        frame = ColorClip(size=(int(img_clip.w + 20), int(img_clip.h + 20)), color=PURPLE).with_duration(SLIDE_DURATION)
        frame = frame.with_position((int(W*0.05 - 10), int(H*0.1 - 10)))
        white_bg = ColorClip(size=(int(img_clip.w + 10), int(img_clip.h + 10)), color=WHITE).with_duration(SLIDE_DURATION)
        white_bg = white_bg.with_position((int(W*0.05 - 5), int(H*0.1 - 5)))

        import re
        title_text = img_name.split('.')[0]
        title_text = re.sub(r'^\d+', '', title_text).replace('_', ' ').strip().upper()
        
        title_img = _create_text_image(title_text, int(W*0.4), 100, 70, PURPLE)
        title_clip = ImageClip(np.array(title_img)).with_duration(SLIDE_DURATION)
        title_clip = title_clip.with_position((int(W*0.55), int(H*0.2)))
        
        sep = ColorClip(size=(int(W*0.4), 5), color=YELLOW).with_duration(SLIDE_DURATION)
        sep = sep.with_position((int(W*0.55), int(H*0.35)))
        
        desc_img = _create_text_image(description, int(W*0.4), 400, 45, (0,0,0))
        desc_clip = ImageClip(np.array(desc_img)).with_duration(SLIDE_DURATION)
        desc_clip = desc_clip.with_position((int(W*0.55), int(H*0.4)))
        
        clips.append(CompositeVideoClip([bg, frame, white_bg, img_clip, title_clip, sep, desc_clip]))

    final_video = concatenate_videoclips(clips, method="compose")
    final_video.write_videofile(output_name, fps=FPS, codec="libx264")
    print(f"Success! Your Grand Video Guide is ready: {output_name}")

    # Final Video
    final_video = concatenate_videoclips(clips, method="compose")
    final_video.write_videofile(output_name, fps=FPS, codec="libx264")
    print(f"Success! Your Grand Video Guide is ready: {output_name}")

if __name__ == "__main__":
    image_dir = os.path.join("manual", "screenshots")
    if not os.path.exists(image_dir):
        print(f"Error: Folder '{image_dir}' not found.")
    else:
        create_manual_video(image_dir)
