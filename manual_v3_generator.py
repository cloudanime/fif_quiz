import os
import subprocess
import sys
import json

def install(package):
    subprocess.check_call([sys.executable, "-m", "pip", "install", package])

try:
    from fpdf import FPDF
except ImportError:
    print("Installing fpdf2...")
    install('fpdf2')
    from fpdf import FPDF

class ManualPDF(FPDF):
    def __init__(self, data):
        super().__init__(orientation='P', unit='mm', format='A4')
        self.data = data
        self.set_margins(20, 20, 20) # 2cm margins
        self.set_auto_page_break(auto=True, margin=20)
        
    def header(self):
        if hasattr(self, 'data') and 'header' in self.data:
            h = self.data['header']
            self.set_font('helvetica', '', h.get('fontSize', 8))
            self.set_text_color(100, 100, 100)
            text = self.clean_text(h.get('text', ''))
            self.cell(0, 10, text, 0, 0, 'R' if h.get('alignment') == 'right' else 'C')
            self.ln(10)

    def footer(self):
        if hasattr(self, 'data') and 'footer' in self.data:
            f = self.data['footer']
            self.set_y(-15)
            self.set_font('helvetica', 'I', f.get('fontSize', 8))
            self.set_text_color(100, 100, 100)
            text = f.get('text', '').replace('[page]', str(self.page_no()))
            text = self.clean_text(text)
            self.cell(0, 10, text, 0, 0, 'C')

    def hex_to_rgb(self, hex_str):
        if not hex_str or not isinstance(hex_str, str):
            return (0, 0, 0)
        hex_str = hex_str.lstrip('#')
        if len(hex_str) == 3:
            hex_str = ''.join([c*2 for c in hex_str])
        if len(hex_str) != 6:
            return (0, 0, 0)
        return tuple(int(hex_str[i:i+2], 16) for i in (0, 2, 4))

    def clean_text(self, text):
        if not isinstance(text, str):
            return ""
        # Replace common special characters
        text = text.replace('‘', "'").replace('’', "'").replace('“', '"').replace('”', '"').replace('–', '-')
        # Remove emojis and other non-latin1 characters
        return text.encode('latin-1', 'ignore').decode('latin-1')

def generate_manual_v3(data, output_name="app_user_manual_v3.pdf"):
    pdf = ManualPDF(data)
    pdf.add_page()
    
    styles = data.get('styles', {})
    
    for block in data.get('content', []):
        text_data = block.get('text', '')
        style_key = block.get('style', 'body')
        
        # Determine style properties
        if isinstance(style_key, dict):
            s = style_key
        else:
            s = styles.get(style_key, styles.get('body', {}))
        
        # Spacing
        if s.get('marginTop'):
            pdf.ln(s.get('marginTop') / 3) # Scale down for PDF mm
            
        # Font settings
        font_size = s.get('fontSize', 11)
        is_bold = s.get('bold', False)
        color_hex = s.get('color', '#000000')
        alignment = s.get('alignment', 'L')
        if alignment == 'center': alignment = 'C'
        elif alignment == 'right': alignment = 'R'
        else: alignment = 'L'
        
        rgb = pdf.hex_to_rgb(color_hex)
        pdf.set_text_color(*rgb)
        pdf.set_font('helvetica', 'B' if is_bold else '', font_size)
        
        # Handle complex text (list with bold parts)
        if isinstance(text_data, list):
            for part in text_data:
                if isinstance(part, dict):
                    p_text = pdf.clean_text(part.get('text', ''))
                    p_bold = part.get('bold', False)
                    pdf.set_font('helvetica', 'B' if p_bold else '', font_size)
                    pdf.write(5 * s.get('lineHeight', 1.0), p_text)
                else:
                    p_text = pdf.clean_text(part)
                    pdf.set_font('helvetica', '', font_size)
                    pdf.write(5 * s.get('lineHeight', 1.0), p_text)
            pdf.ln(s.get('marginBottom', 10) / 2)
        else:
            # Simple text block
            p_text = pdf.clean_text(text_data)
            pdf.multi_cell(0, 5 * s.get('lineHeight', 1.2), p_text, 0, alignment)
            pdf.ln(s.get('marginBottom', 10) / 2)

    pdf.output(output_name)
    print(f"Success! Manual v3.0 generated: {output_name}")

if __name__ == "__main__":
    manual_json = {
      "format": "A4",
      "orientation": "portrait",
      "margin": {
        "top": "2cm",
        "bottom": "2cm",
        "left": "2cm",
        "right": "2cm"
      },
      "header": {
        "text": "Legacy Quiz Mobile & Web App - User Manual v3.0",
        "fontSize": 8,
        "alignment": "right"
      },
      "footer": {
        "text": "Celebrating 100 Years of God's Grace | Page [page]",
        "fontSize": 8,
        "alignment": "center"
      },
      "styles": {
        "h1": {
          "fontSize": 20,
          "bold": True,
          "color": "#2C3E50",
          "alignment": "center",
          "marginBottom": 12,
          "marginTop": 10
        },
        "h2": {
          "fontSize": 16,
          "bold": True,
          "color": "#8B0000",
          "marginTop": 15,
          "marginBottom": 8
        },
        "h3": {
          "fontSize": 14,
          "bold": True,
          "color": "#2C3E50",
          "marginTop": 10,
          "marginBottom": 6
        },
        "body": {
          "fontSize": 11,
          "lineHeight": 1.4,
          "marginBottom": 10
        }
      },
      "content": [
        {
          "text": "Legacy Quiz User Guide",
          "style": "h1"
        },
        {
          "text": "Comprehensive Manual for Mobile (Android) & Web App Versions",
          "style": {
            "fontSize": 14,
            "color": "#555",
            "alignment": "center",
            "marginBottom": 180
          }
        },
        {
          "text": "* For Guidance and not exhaustive.",
          "style": {
            "fontSize": 9,
            "color": "#888",
            "alignment": "center",
            "marginBottom": 20
          }
        },
        {
          "text": "Instructions",
          "style": "h2"
        },
        {
          "text": "Guidance on playing different Game versions, which include:",
          "style": "body"
        },
        {
          "text": "\u2022 Offline Single Player\n\u2022 Offline Multiple Players\n\u2022 Online Single Player\n\u2022 Online Individual Challenge\n\u2022 Online Team Challenge",
          "style": "body"
        },
        {
          "text": "The Legacy Continues",
          "style": "h2"
        },
        {
          "text": "\"Message from Visionary and Founder, Archbishop Professor Ezekiel H. Guti.\"",
          "style": {
            "fontSize": 12,
            "bold": True,
            "color": "#2C3E50",
            "alignment": "center",
            "marginBottom": 20
          }
        },
        {
          "text": "Offline Game Play",
          "style": "h2"
        },
        {
          "text": "Synchronize your local database by clicking any of the 2 buttons below (Sync Cloud or Load Package). Once done you do not need internet connection to enjoy the game, just start the game.",
          "style": "body"
        },
        {
          "text": "Renaming players is optional.",
          "style": "body"
        },
        {
          "text": "Game Setup & Questions",
          "style": "h2"
        },
        {
          "text": "Each game has a randomly selected 100 questions from our database. You determine how many questions will be played for your game session.",
          "style": "body"
        },
        {
          "text": "The quiz grid layout is categorized as follows:\n\u2022 Questions 1-70: Multiple Choice\n\u2022 Questions 71-80: Image Based\n\u2022 Questions 81-100: Open Ended / Structured",
          "style": "body"
        },
        {
          "text": "Scoreboard is located at the bottom of the questions grid. You can change the grid's width, height or font size by using the slides above.",
          "style": "body"
        },
        {
          "text": "Marking Answers",
          "style": "h2"
        },
        {
          "text": "Correct answers and their sources are provided for guidance. Use the designated grid to mark participants' answers. All players in a session answer the same questions.",
          "style": "body"
        },
        {
          "text": "Winner Reveal & Animation",
          "style": "h2"
        },
        {
          "text": "Cumulative scores are displayed via a dynamic bar chart. After the race, the winner is announced with a trophy presentation. You can replay the animation as needed.",
          "style": "body"
        },
        {
          "text": "Online Multiplayer Modes",
          "style": "h2"
        },
        {
          "text": "Online Individual Challenge:\n1. Host generates a session code.\n2. Participants join using the code.\n3. Scores are tracked individually.\n\nOnline Team Challenge:\n1. Create teams (max 5 per team).\n2. Participants join specific teams.\n3. Individual scores aggregate into team totals.",
          "style": "body"
        },
        {
          "text": "Contributing to the Legacy",
          "style": "h2"
        },
        {
          "text": "Registered users can submit questions (Question, Answer, Source) for administrative review. Approved questions are added to the global database.",
          "style": "body"
        },
        {
          "text": "\u00a9 Legacy Quiz \u2014 A Ministry of the Archbishop Professor Ezekiel H. Guti",
          "style": {
            "fontSize": 9,
            "color": "#888",
            "alignment": "center",
            "marginTop": 40
          }
        }
      ]
    }
    generate_manual_v3(manual_json)
