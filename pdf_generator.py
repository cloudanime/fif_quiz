import os
import subprocess
import sys

def install(package):
    subprocess.check_call([sys.executable, "-m", "pip", "install", package])

try:
    from fpdf import FPDF
except ImportError:
    print("Installing fpdf...")
    install('fpdf2')
    from fpdf import FPDF

class UserManualPDF(FPDF):
    def header(self):
        # Draw background color for the whole page
        self.set_fill_color(253, 239, 255) # Light Pink
        self.rect(0, 0, 210, 297, 'F')
        
        self.set_font('Arial', 'B', 15)
        self.set_text_color(69, 14, 78) # Deep Purple
        self.cell(0, 10, 'Legacy Quiz - Official User Manual', 0, 1, 'C')
        # Yellow header line
        self.set_draw_color(255, 214, 0) # Yellow
        self.set_line_width(1)
        self.line(10, 20, 200, 20)
        self.ln(10)

    def footer(self):
        self.set_y(-15)
        self.set_font('Arial', 'I', 8)
        self.set_text_color(69, 14, 78)
        self.cell(0, 10, f'Page {self.page_no()}', 0, 0, 'C')

def create_manual_pdf(image_folder, output_name="app_user_manual.pdf"):
    pdf = UserManualPDF()
    pdf.set_auto_page_break(auto=True, margin=15)
    
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

    print("Generating Standardized Grand PDF Manual...")
    
    # Title Page
    pdf.add_page()
    
    pdf.set_font('Arial', 'B', 32)
    pdf.set_text_color(69, 14, 78) # Purple
    pdf.ln(60)
    pdf.cell(0, 20, 'Legacy Quiz', 0, 1, 'C')
    
    # Yellow separator
    pdf.set_draw_color(255, 214, 0)
    pdf.set_line_width(1.5)
    pdf.line(50, pdf.get_y(), 160, pdf.get_y())
    
    pdf.ln(10)
    pdf.set_font('Arial', '', 18)
    pdf.cell(0, 10, 'User Guide & Documentation', 0, 1, 'C')
    
    pdf.ln(30)
    pdf.set_font('Arial', 'I', 14)
    pdf.cell(0, 10, 'Celebrating 100 Years of God\'s Grace', 0, 1, 'C')

    # Asterisk footer for Title Page
    pdf.set_y(-30)
    pdf.set_font('Arial', 'I', 10)
    pdf.cell(0, 10, '* For Guidance and not exhaustive.', 0, 1, 'C')
    
    # Slides
    import re
    valid_image_count = 0
    
    # Fixed dimensions for ALL images (Adjusted to fit 2 per page without overlap)
    IMG_W = 70
    IMG_H = 110
    
    for img_name, description in slides_data:
        img_path = os.path.join(image_folder, img_name)
        if not os.path.exists(img_path):
            print(f"Warning: {img_path} not found. Skipping.")
            continue
            
        # Decide position
        if valid_image_count % 2 == 0:
            pdf.add_page()
            start_y = 30
        else:
            start_y = 155
            # --- DIVIDING LINE ---
            pdf.set_draw_color(255, 214, 0) # Yellow
            pdf.set_line_width(0.5)
            pdf.line(10, 145, 200, 145)
        
        valid_image_count += 1
        
        # --- LEFT COLUMN: Screenshot ---
        # Add a white frame for the image
        pdf.set_fill_color(255, 255, 255)
        pdf.rect(13, start_y - 2, IMG_W + 4, IMG_H + 4, 'F')
        pdf.set_draw_color(69, 14, 78) # Purple Border
        pdf.rect(13, start_y - 2, IMG_W + 4, IMG_H + 4, 'D')
        
        pdf.image(img_path, x=15, y=start_y, w=IMG_W, h=IMG_H) 
        
        # --- RIGHT COLUMN: Description ---
        pdf.set_xy(105, start_y)
        
        # Clean up Title
        title_text = img_name.split('.')[0]
        title_text = re.sub(r'^\d+', '', title_text).replace('_', ' ')
        
        # Add Title
        pdf.set_font('Arial', 'B', 16)
        pdf.set_text_color(69, 14, 78) # Purple
        pdf.multi_cell(90, 10, title_text.strip().upper())
        
        # Yellow separator line
        pdf.set_draw_color(255, 214, 0) # Yellow
        pdf.set_line_width(1)
        pdf.line(105, pdf.get_y() + 1, 195, pdf.get_y() + 1)
        pdf.ln(8)
        
        # Add Description
        pdf.set_x(105)
        pdf.set_font('Arial', '', 12)
        pdf.set_text_color(0, 0, 0) # Black for readability
        pdf.multi_cell(90, 7, description)

    pdf.output(output_name)
    print(f"Success! Your standardized Grand Edition PDF manual is ready: {output_name}")

if __name__ == "__main__":
    image_dir = os.path.join("manual", "screenshots")
    if not os.path.exists(image_dir):
        print(f"Error: Folder '{image_dir}' not found.")
    else:
        create_manual_pdf(image_dir)
