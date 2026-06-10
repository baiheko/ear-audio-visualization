import sys
from PyQt6.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, 
                             QHBoxLayout, QLabel, QFrame, QPushButton)
from PyQt6.QtCore import Qt

class ModernCard(QFrame):
    def __init__(self, title, desc, icon, color, width=350, height=130, is_large=True, parent=None):
        super().__init__(parent)
        self.setFixedSize(width, height)
        # 修改：增加鼠标手型，提示用户这是可点击的交互元素
        self.setCursor(Qt.CursorShape.PointingHandCursor)
        self.setStyleSheet(f"""
            ModernCard {{
                background-color: {color};
                border-radius: 16px;
                border: 1px solid rgba(255, 255, 255, 0.05);
            }}
            ModernCard:hover {{ background-color: {color}dd; border: 1px solid #b070ff; }}
        """)
        
        layout = QVBoxLayout(self)
        layout.setContentsMargins(15, 15, 15, 15)
        layout.setSpacing(5)
        
        icon_label = QLabel(icon)
        icon_label.setStyleSheet("font-size: 32px; background: transparent;")
        icon_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(icon_label)
        
        title_label = QLabel(title)
        title_label.setStyleSheet("color: white; font-size: 18px; font-weight: 800; background: transparent;")
        title_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(title_label)
        
        if is_large:
            desc_label = QLabel(desc)
            desc_label.setStyleSheet("color: #a0a0b5; font-size: 12px; background: transparent;")
            desc_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
            layout.addWidget(desc_label)

    # 绑定点击事件，这里你可以后续加入跳转逻辑
    def mousePressEvent(self, event):
        print(f"点击了模块: {self.findChild(QLabel).text()}")

class YiErMainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("易耳 - 多模态感知助手")
        self.setFixedSize(393, 852)
        self.setStyleSheet("background-color: #0b0e14;")

        central = QWidget()
        self.setCentralWidget(central)
        main_layout = QVBoxLayout(central)
        main_layout.setContentsMargins(20, 80, 20, 30)
        main_layout.setSpacing(25) # 适当加大模块间距

        # 标题区
        header = QLabel("易耳 (Ear)")
        header.setStyleSheet("color: #b070ff; font-size: 36px; font-weight: 900;")
        header.setAlignment(Qt.AlignmentFlag.AlignCenter)
        slogan = QLabel("让音乐看得见 · 触得到")
        slogan.setStyleSheet("color: #666; font-size: 13px; letter-spacing: 1px;")
        slogan.setAlignment(Qt.AlignmentFlag.AlignCenter)
        main_layout.addWidget(header)
        main_layout.addWidget(slogan)
        main_layout.addSpacing(20)
        
        # 核心功能模块：将“现场演唱会”直接作为“开始体验”入口
        cards_data = [
            ("开始体验 (现场模式)", "实时同步歌词与氛围反馈", "🎵", "#1a1e2e"),
            ("AI 问答助手", "智能解析现场环境状态", "💬", "#1a1e2e")
        ]
        for t, d, i, c in cards_data:
            card = ModernCard(t, d, i, c, width=350, height=130, is_large=True)
            main_layout.addWidget(card, alignment=Qt.AlignmentFlag.AlignCenter)

        # 辅助功能模块
        extra_layout = QHBoxLayout()
        extra_layout.setSpacing(15)
        extra_cards = [
            ("教学指南", "🎓", "#1a1e2e"),
            ("系统设置", "⚙️", "#1a1e2e")
        ]
        for t, i, c in extra_cards:
            card = ModernCard(t, "", i, c, width=167, height=100, is_large=False)
            extra_layout.addWidget(card)
            
        main_layout.addLayout(extra_layout)
        main_layout.addStretch()

if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = YiErMainWindow()
    window.show()
    sys.exit(app.exec())