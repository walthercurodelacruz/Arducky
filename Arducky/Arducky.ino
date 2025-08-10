// ====== HID key codes y modificadores (USB HID) ======
#define KEY_LEFT_CTRL   0x01
#define KEY_LEFT_SHIFT  0x02
#define KEY_LEFT_ALT    0x04
#define KEY_LEFT_GUI    0x08
#define KEY_RIGHT_CTRL  0x10
#define KEY_RIGHT_SHIFT 0x20
#define KEY_RIGHT_ALT   0x40
#define KEY_RIGHT_GUI   0x80

#define KEY_RIGHT_ARROW 0x4F
#define KEY_LEFT_ARROW  0x50
#define KEY_DOWN_ARROW  0x51
#define KEY_UP_ARROW    0x52
#define KEY_ESC         0x29   // <-- corregido
#define KEY_F1          0x3A
#define KEY_F2          0x3B
#define KEY_F3          0x3C
#define KEY_F4          0x3D
#define KEY_F5          0x3E
#define KEY_F6          0x3F
#define KEY_F7          0x40
#define KEY_F8          0x41
#define KEY_F9          0x42
#define KEY_F10         0x43
#define KEY_F11         0x44
#define KEY_F12         0x45

#define KEY_DEL         0x4C
#define KEY_INS         0x49
#define KEY_END         0x4D
#define KEY_HOME        0x4A
#define KEY_PGDN        0x4E
#define KEY_PGUP        0x4B

#define KEY_BACKSPC     0x2A
#define KEY_TAB         0x2B
#define KEY_ENTER       0x28
#define KEY_SPC         0x2C
#define KEY_MINUS       0x2D
#define KEY_EQUAL       0x2E
#define KEY_COMMA       0x36
#define KEY_PERIOD      0x37
#define KEY_SLASH       0x38    // ojo: verifica layout si no es US
#define KEY_BACKSLASH   0x31    // ojo: en algunos layouts es distinto

#define KEY_NONE        0x00    // verdadero “ninguna tecla”

// ====== Reporte HID (8 bytes): [mods,reserved,k1,k2,k3,k4,k5,k6] ======
static const uint8_t REPORT_LEN = 8;
static const uint8_t TAP_DELAY  = 5;  // ms entre press/release
uint8_t buf[REPORT_LEN] = {0};

// ====== Helpers ======
inline void sendReport() { Serial.write(buf, REPORT_LEN); }
inline void releaseAll() { memset(buf, 0, sizeof(buf)); sendReport(); delay(TAP_DELAY); }
inline void tap(uint8_t mods, uint8_t key) {
  buf[0] = mods; buf[2] = key; sendReport(); delay(TAP_DELAY);
  releaseAll();
}

// Mapear un carácter ASCII simple a (mods,key). Ajustado a layout ES/US básico.
// Si usas otro layout, revisa los casos comentados.
void typeChar(char c) {
  uint8_t mods = 0, key = 0;

  if (c >= 'a' && c <= 'z')           key = c - 'a' + 4;
  else if (c >= 'A' && c <= 'Z')     { mods = KEY_LEFT_SHIFT; key = c - 'A' + 4; }
  else if (c >= '1' && c <= '9')      key = c - 19;      // '1'->0x1E … '9'->0x26
  else if (c == '0')                  key = 0x27;
  else if (c == ' ')                  key = KEY_SPC;
  else if (c == '.')                  key = KEY_PERIOD;
  else if (c == ',')                  key = KEY_COMMA;
  else if (c == '-')                  key = KEY_MINUS;
  else if (c == '_')                 { mods = KEY_LEFT_SHIFT; key = KEY_MINUS; }
  else if (c == '=')                  key = KEY_EQUAL;
  else if (c == '+')                 { mods = KEY_LEFT_SHIFT; key = KEY_EQUAL; }
  else if (c == '<')                 { mods = KEY_LEFT_SHIFT; key = KEY_COMMA; }
  else if (c == '>')                 { mods = KEY_LEFT_SHIFT; key = KEY_PERIOD; }
  else if (c == ';')                  key = 0x33;        // ;  (verifica layout)
  else if (c == '/')                  key = KEY_SLASH;   // /  (verifica layout)
  else if (c == '\\')                 key = KEY_BACKSLASH; // \ (verifica layout)
  else if (c == '(')                { mods = KEY_LEFT_SHIFT; key = 0x26; }
  else if (c == ')')                { mods = KEY_LEFT_SHIFT; key = 0x27; }
  else if (c == '[')                { mods = KEY_RIGHT_ALT;  key = 0x25; } // ES: AltGr + [
  else if (c == ']')                { mods = KEY_RIGHT_ALT;  key = 0x26; } // ES: AltGr + ]
  else if (c == '{')                { mods = KEY_RIGHT_ALT;  key = 0x24; } // ES: AltGr + {
  else if (c == '}')                { mods = KEY_RIGHT_ALT;  key = 0x27; } // ES: AltGr + }
  else if (c == '|')                { mods = KEY_RIGHT_ALT;  key = 0x64; } // “non-US #” key
  else if (c == '&')                { mods = KEY_LEFT_SHIFT; key = 0x24; } // Shift + 7 en US
  else                               key  = KEY_NONE;

  if (key != KEY_NONE) tap(mods, key);
}

void typeText(const char* s) { while (*s) typeChar(*s++); }

// ==== Atajos “humanos”, compatibles con tu API original ====
void DELAY(unsigned ms) { delay(ms); }
void ENTER()            { tap(0, KEY_ENTER); }
void TAB()              { tap(0, KEY_TAB); }
void ALT_F2()           { tap(KEY_LEFT_ALT, KEY_F2); }

void WINDOWS(const char* c) {
  char k = (c && c[0]) ? c[0] : 0;
  if (k >= 'a' && k <= 'z') tap(KEY_LEFT_GUI, k - 'a' + 4);
  else if (k >= 'A' && k <= 'Z') tap(KEY_LEFT_GUI | KEY_LEFT_SHIFT, k - 'A' + 4);
}

void CTRL_ALT(const char* c) {
  char k = (c && c[0]) ? c[0] : 0;
  if (k >= 'a' && k <= 'z') tap(KEY_LEFT_CTRL | KEY_LEFT_ALT, k - 'a' + 4);
  else if (k >= 'A' && k <= 'Z') tap(KEY_LEFT_CTRL | KEY_LEFT_ALT | KEY_LEFT_SHIFT, k - 'A' + 4);
}

// Usa Delete (0x4C) con Ctrl+Alt
void CTRL_ALT_DEL() { tap(KEY_LEFT_CTRL | KEY_LEFT_ALT, KEY_DEL); }

// ====== Demo ======
void setup() {
  Serial.begin(9600);
  delay(300);

  DELAY(1000);
  WINDOWS("r");
  DELAY(120);
  typeText("cmd");
  ENTER();
  DELAY(600);
  typeText("Arduino Ducky Listo");
  ENTER();
  typeText("ping 8.8.8.8");
  ENTER();
}

void loop() { /* nada */ }
