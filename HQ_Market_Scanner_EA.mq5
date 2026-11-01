//+------------------------------------------------------------------+
//|                                        HQ_Market_Scanner_EA.mq5  |
//|  แสดงทุก Symbol ใน Market Watch พร้อม                             |
//|   - % การเปลี่ยนแปลง (ค่าเริ่มต้น = เทียบราคาปิดเมื่อวาน)         |
//|   - ราคาปัจจุบัน                                                  |
//|   - Order Block "ล่าสุดที่เกิดขึ้น" (Bull/Bear) + Retest + OB Zone |
//|                                                                  |
//|  v2.01: ATR Quality Filter (Displacement >= MinDispStrength x ATR)|
//|  v2.02: Swing Quality Filter                                     |
//|  v2.03: Dashboard แบบเลื่อนได้ (2 กรอบสีฟ้า: US / อื่นๆ)           |
//|         เลื่อนด้วยล้อเมาส์ (เมื่อเมาส์อยู่ในกรอบ) หรือปุ่ม ▲ ▼      |
//|  v2.04: Auto Fibonacci (M5) จาก Qualified Swing High/Low          |
//|         แสดง Golden Zone (0.618 - 0.786) แทนคอลัมน์ Bars Ago      |
//|  v2.05: UX/UI ใหม่ (สไตล์ SwingTradeBOT): กรอบเดียวพื้นดำ + Consolas|
//|         SYMBOL ตรึง / คอลัมน์เลื่อนแนวนอน (Shift+ล้อเมาส์ หรือ ◄ ►)  |
//|         คลิกแถว = เลือก, ดับเบิลคลิก = แผง Detail                   |
//|  v2.06: ลบ Auto Fibonacci / Golden Zone ออกทั้งหมด                 |
//|         ระบบ OB ใหม่ = ตรรกะเดียวกับ Pine "ORDER BLOCK QUALITY"     |
//|         (Quality Score / Grade A+ A B C / ATR Strength / OB Width)   |
//|         ดับเบิลคลิกที่ Symbol = หน้าต่าง Advanced OB Dashboard       |
//|  v2.07: ลบปุ่มลูกศร ใช้ลูกกลิ้งเมาส์อย่างเดียว / หัวกรอบเหลือ US Stock, Other |
//|         เพิ่มคอลัมน์ Trend (Bull/Bear) 1D 1H 30M 15M 1M ต่อจาก STATUS    |
//|         Shift+ลูกกลิ้ง = เลื่อนซ้าย-ขวาแบบสมูท (แอนิเมชันเป็นพิกเซล)        |
//|  v2.08: แอนิเมชันเปิด/ปิดหน้าต่าง Advanced OB Dashboard                  |
//|         (Fade จากสีพื้นกราฟ + เลื่อนขึ้น 14px, Ease-out)                 |
//+------------------------------------------------------------------+
#property copyright "HQ-OB MT5 Scanner"
#property version   "2.08"

//---------------------------------------------------------------- Enums
enum ENUM_MITIGATION_METHOD
  {
   WICK_TOUCH,               // Wick Touch
   CLOSE_INSIDE_OB,          // Candle Close Inside OB
   FULL_BODY_CLOSE_THROUGH   // Full Body Close Through OB
  };

enum ENUM_OPEN_REF
  {
   OPEN_PREV_CLOSE, // เทียบราคาปิดเมื่อวาน (เหมือน TradingView)
   OPEN_DAILY,      // เปิดแท่งรายวัน (D1) ปัจจุบัน
   OPEN_WEEKLY,     // เปิดแท่งรายสัปดาห์ (W1) ปัจจุบัน
   OPEN_SESSION     // เปิดหลัง gap ล่าสุด
  };

enum ENUM_HQ_SORT
  {
   SORT_MARKET_WATCH,  // ตามลำดับใน Market Watch
   SORT_PCT_DESC,      // % มากไปน้อย
   SORT_ABS_PCT_DESC,  // |%| มากไปน้อย
   SORT_OB_FIRST       // OB ที่ยังไม่ Retest + ใหม่สุดก่อน
  };

//---------------------------------------------------------------- Inputs
input group "Scan Scope"
input ENUM_TIMEFRAMES ScanTimeframe      = PERIOD_CURRENT; // Timeframe (CURRENT = TF ของชาร์ตที่ลง EA)
input int    LookbackBars                = 1000;           // ยิ่งมากยิ่งใกล้เคียงอินดิเคเตอร์
input bool   UseMarketWatchOnly          = true;

input group "% Change Reference"
input ENUM_OPEN_REF OpenReference        = OPEN_PREV_CLOSE;
input int    SessionGapHours             = 2;

input group "Structure (BOS)  [เหมือนอินดิเคเตอร์ HQ-OB-Q]"
input int    SwingLength                 = 5;
input int    MaxCandidateAge             = 50;    // Max Bars Waiting for BOS Confirmation

input group "Displacement"
input int    AtrLength                   = 14;
input double MinDispStrength             = 1.0;   // Minimum Displacement Strength (x ATR)

input group "Imbalance (FVG)"
input int    MaxObToFvgDistance          = 3;

input group "Mitigation"
input ENUM_MITIGATION_METHOD MitigationMethod = CLOSE_INSIDE_OB;
input bool   ShowMitigatedOB             = true;  // true = Latest OB รวมที่ Mitigate แล้ว (สถานะ Retested), false = เฉพาะที่ยัง Fresh

input group "ATR Strength"
input double MinAtrShow                  = 3.0;   // Minimum ATR Strength to Display (x ATR)
input double AtrFullScore                = 5.0;   // ATR Strength ที่ได้คะแนนเต็ม (Extreme Threshold)

input group "OB Quality"
input double MinQuality                  = 0.0;   // Minimum Quality Score to Display (0-100)
input double IdealWidthATR               = 1.0;   // Ideal OB Width (x ATR) - ได้คะแนนเต็ม
input double MaxWidthATR                 = 3.0;   // Max OB Width (x ATR) - กว้างกว่านี้ตัดทิ้ง
input double BosIdealATR                 = 0.5;   // Ideal BOS Break Distance (x ATR)
input double FvgIdealATR                 = 0.3;   // Ideal FVG Size (x ATR)
input double WeightAtr                   = 30.0;  // Weight: ATR Strength
input double WeightBosFvg                = 25.0;  // Weight: BOS + FVG
input double WeightFresh                 = 20.0;  // Weight: Unmitigated (Freshness)
input double WeightWidth                 = 25.0;  // Weight: OB Width

input group "Dashboard"
input bool   ShowAllSymbols              = true;   // true = แสดงทุก symbol, false = เฉพาะที่มี OB
input bool   ShowOnlyNotRetested         = false;  // (ShowAllSymbols=false) เฉพาะ OB ที่ยังไม่ Retest
input ENUM_HQ_SORT SortMode              = SORT_PCT_DESC;
input int    ViewRowsUS                  = 12;     // จำนวนแถวสูงสุดที่เห็นในกรอบ US (เกินนี้เลื่อนได้)
input int    ViewRowsOther               = 10;     // จำนวนแถวสูงสุดที่เห็นในกรอบอื่นๆ
input int    WheelStep                   = 3;      // เลื่อนแนวตั้งต่อ 1 notch ของลูกกลิ้ง (แถว)
input int    HScrollPx                   = 90;     // เลื่อนแนวนอนต่อ 1 notch ของ Shift+ลูกกลิ้ง (พิกเซล, เลื่อนแบบสมูท)
input double CharPx                      = 7.0;    // ความกว้างตัวอักษร Consolas (px) ใช้ตัดข้อความที่ล้นขอบตอนเลื่อน
input int    TrendBars                   = 300;    // จำนวนแท่งที่ใช้หา Trend ต่อ Time frame
input color  FrameColor                  = C'0,170,255'; // สีกรอบ / หัวข้อ
input string FontName                    = "Consolas";   // ฟอนต์ Dashboard
input int    RefreshSeconds              = 10;
input int    DashX                       = 15;
input int    DashY                       = 25;

input group "US Stock Classification"
input string UsKeywords                  = "US;USA;NASDAQ;NYSE;AMEX;ARCA;BATS;XNAS;XNYS;UNITED STATES";
input bool   RequireStockInPath          = true;   // true = Path ต้องมีคำว่า Stock/Share/Equit ด้วย

//---------------------------------------------------------------- Globals
string   g_symbols[];
datetime g_lastBar[];
ENUM_TIMEFRAMES g_tf;
string   PFX = "HQOBS_";

struct ScanResult
  {
   string   symbol;
   int      digits;
   bool     pctValid;
   double   price;
   double   openPrice;
   double   pct;
   bool     hasOB;
   int      dir;          // 1 = Bull, -1 = Bear
   double   obHigh;
   double   obLow;
   datetime confirmTime;
   int      barsAgo;
   bool     retested;     // Mitigate แล้ว
   bool     us;           // true = หุ้นอเมริกา
   double   score;        // Quality Score 0-100
   string   grade;        // A+ / A / B / C
   double   atrX;         // ATR Strength (x ATR)
   double   widthX;       // OB Width (x ATR)
   double   bosX;         // ระยะ BOS (x ATR)
   double   fvgX;         // ขนาด FVG (x ATR)
   int      touches;      // จำนวนครั้งที่ราคาแตะโซนแต่ยังไม่ Mitigate
   int      trend[5];     // Trend 1D, 1H, 30M, 15M, 1M (1 = Bull, -1 = Bear, 0 = n/a)
  };

ScanResult g_cache[];

//--- Dashboard state
#define ROW_H    16
#define N_COLS   10                       // PRICE, % CHG, LATEST OB, OB ZONE, STATUS, TREND 1D/1H/30M/15M/1M
#define POP_W    390                      // หน้าต่าง Advanced OB Dashboard (ดับเบิลคลิก)
#define POP_H    202
#define SYM_W    90                       // ความกว้างคอลัมน์ SYMBOL (ตรึง)
#define PANEL_W  780
#define VIEW_W   (PANEL_W - 16 - SYM_W)   // ความกว้างพื้นที่คอลัมน์ที่เลื่อนได้

ScanResult g_us[], g_ot[];          // รายการที่แยกกลุ่มแล้ว (เรียงตาม SortMode)
bool       g_isUs[];
string     g_usKw[];
int        g_scrUs = 0, g_scrOt = 0;
double     g_hOff = 0, g_hTarget = 0, g_hMax = 0;   // เลื่อนแนวนอนเป็นพิกเซล (ตำแหน่งจริง / เป้าหมาย / สูงสุด)
bool       g_anim = false;                            // กำลังเลื่อนแบบแอนิเมชัน
bool       g_light = false;                           // true = วาดซ้ำแบบเบา (อัปเดต object เดิม ไม่ลบทิ้งทั้งหมด)
ulong      g_lastScanMs = 0;
datetime   g_trBar[];                                 // แท่งล่าสุดที่คำนวณ Trend แล้ว (symbol*5 + tf)
int        g_trVal[];                                 // ผล Trend ที่ cache ไว้
bool       g_origMouseScroll = true;
bool       g_origEvMove = false, g_origEvWheel = true;
bool       g_inside = false;
int        g_found = 0, g_withOB = 0;
int        g_usTop = 0, g_usBot = 0, g_otTop = 0, g_otBot = 0;
int        g_usRow0 = 0, g_otRow0 = 0, g_viewUS = 1, g_viewOT = 1;

string     g_sel = "";
bool       g_detail = false;      // หน้าต่าง Advanced OB Dashboard เปิดอยู่หรือไม่ (สถานะที่ผู้ใช้ต้องการ)
string     g_detailSym = "";
int        g_popX = 0, g_popY = 0, g_popH = POP_H;
string     g_lastClickSym = "";
ulong      g_lastClickMs = 0;

//--- Popup animation
double     g_popT    = 0.0;        // ความคืบหน้า 0 = ปิดสนิท, 1 = เปิดเต็ม
double     g_pe      = 1.0;        // ค่า ease-out ที่ใช้วาดจริง
bool       g_popAnim = false;      // กำลังเล่นแอนิเมชันอยู่
color      g_pbg     = clrBlack;   // สีพื้นกราฟ (ปลายทางของ Fade)

color C_BG     = C'5,5,5';
color C_HDR    = C'215,215,215';
color C_MUTED  = C'125,125,125';
color C_GREEN  = C'0,230,90';
color C_RED    = C'255,60,60';
color C_YELLOW = C'255,215,0';
color C_SELBG  = C'18,40,62';

//--- ผสมสี a -> b ตาม t (0..1)
color Blend(const color a, const color b, const double t)
  {
   int ar = (int)a & 0xFF, ag = ((int)a >> 8) & 0xFF, ab = ((int)a >> 16) & 0xFF;
   int br = (int)b & 0xFF, bg = ((int)b >> 8) & 0xFF, bb = ((int)b >> 16) & 0xFF;
   int r  = (int)MathRound(ar + (br - ar) * t);
   int g  = (int)MathRound(ag + (bg - ag) * t);
   int bl = (int)MathRound(ab + (bb - ab) * t);
   return (color)(r | (g << 8) | (bl << 16));
  }

color PC(const color c) { return Blend(g_pbg, c, g_pe); }   // สีที่ Fade ตามความคืบหน้า

struct PendC             // Candidate ที่รอ BOS
  {
   double hi, lo;
   int    obBar;
   int    dispBar;
   double swingRef;
   double fvgX;          // ขนาด FVG (x ATR)
  };

struct OBI               // OB ที่ยืนยัน BOS แล้ว
  {
   int    dir;
   double hi, lo;
   int    confirmBar;
   bool   mit;
   double atrX;
   double bosX;
   double fvgX;
   double widthX;
   int    touches;
   double score;
  };

//+------------------------------------------------------------------+
int OnInit()
  {
   g_tf = (ScanTimeframe == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)Period() : ScanTimeframe;
   g_origMouseScroll = (bool)ChartGetInteger(0, CHART_MOUSE_SCROLL);
   g_origEvMove      = (bool)ChartGetInteger(0, CHART_EVENT_MOUSE_MOVE);
   g_origEvWheel     = (bool)ChartGetInteger(0, CHART_EVENT_MOUSE_WHEEL);
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   ChartSetInteger(0, CHART_EVENT_MOUSE_WHEEL, true);

   BuildSymbolList();
   EventSetMillisecondTimer(16);      // 16ms = แอนิเมชันเลื่อนซ้าย-ขวา / popup; สแกนตลาดทุก RefreshSeconds ใน OnTimer
   ScanAndDraw();
   g_lastScanMs = GetTickCount64();
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   ChartSetInteger(0, CHART_MOUSE_SCROLL, g_origMouseScroll);
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, g_origEvMove);
   ChartSetInteger(0, CHART_EVENT_MOUSE_WHEEL, g_origEvWheel);
   ObjectsDeleteAll(0, PFX);
  }

void OnTick() {}
void OnTimer()
  {
   // แอนิเมชันเลื่อนแนวนอน: ไหลเข้าหาเป้าหมายแบบ ease-out
   if(g_anim)
     {
      double d = g_hTarget - g_hOff;
      if(MathAbs(d) < 1.0)
        {
         g_hOff  = g_hTarget;
         g_anim  = false;
        }
      else
        {
         double step = d * 0.3;
         if(MathAbs(step) < 1.0) step = (d > 0) ? 1.0 : -1.0;
         g_hOff += step;
        }
      g_light = true;
      DrawDashboard();
      g_light = false;
     }

   // แอนิเมชันเปิด/ปิดหน้าต่าง Advanced OB Dashboard
   if(g_popAnim)
     {
      double target = g_detail ? 1.0 : 0.0;
      if(g_popT < target)      g_popT = MathMin(target, g_popT + 0.09);   // เปิด ~0.2 วินาที
      else if(g_popT > target) g_popT = MathMax(target, g_popT - 0.12);   // ปิดเร็วกว่าเล็กน้อย
      if(g_popT == target) g_popAnim = false;

      g_light = true;
      DrawPopup();
      g_light = false;
      ChartRedraw();
     }

   ulong now = GetTickCount64();
   if(now - g_lastScanMs >= (ulong)RefreshSeconds * 1000)
     {
      g_lastScanMs = now;
      ScanAndDraw();
     }
  }

//+------------------------------------------------------------------+
//| COLUMN LAYOUT (SYMBOL ตรึง, คอลัมน์อื่นเลื่อนแนวนอนได้)             |
//|   0 PRICE  1 % CHG  2 LATEST OB  3 OB ZONE  4 STATUS               |
//+------------------------------------------------------------------+
int ColW(const int c)
  {
   switch(c)
     {
      case 0: return 80;    // PRICE
      case 1: return 80;    // % CHG
      case 2: return 110;   // LATEST OB (+ Grade)
      case 3: return 160;   // OB ZONE
      case 4: return 105;   // STATUS
      case 5: return 56;    // TREND 1D
      case 6: return 56;    // TREND 1H
      case 7: return 56;    // TREND 30M
      case 8: return 56;    // TREND 15M
      case 9: return 56;    // TREND 1M
     }
   return 80;
  }

bool ColRight(const int c)
  {
   return (c == 0 || c == 1);
  }

string ColHdr(const int c)
  {
   switch(c)
     {
      case 0: return "PRICE";
      case 1: return "% CHG";
      case 2: return "LATEST OB";
      case 3: return "OB ZONE";
      case 4: return "STATUS";
      case 5: return "1D";
      case 6: return "1H";
      case 7: return "30M";
      case 8: return "15M";
      case 9: return "1M";
     }
   return "";
  }
//+------------------------------------------------------------------+
//| TREND ต่อ Time frame (1D, 1H, 30M, 15M, 1M)                       |
//|  อิงโครงสร้างเดียวกับ BOS: ปิดทะลุ Swing High ล่าสุด = Bull        |
//|  ปิดทะลุ Swing Low ล่าสุด = Bear (เอาการทะลุล่าสุดเป็น Trend)      |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES TrendTf(const int k)
  {
   switch(k)
     {
      case 0: return PERIOD_D1;
      case 1: return PERIOD_H1;
      case 2: return PERIOD_M30;
      case 3: return PERIOD_M15;
      case 4: return PERIOD_M1;
     }
   return PERIOD_D1;
  }

int ComputeTrend(const string sym, const ENUM_TIMEFRAMES tf, bool &ok)
  {
   ok = false;
   MqlRates r[];
   ArraySetAsSeries(r, false);
   int n = CopyRates(sym, tf, 1, TrendBars, r);
   if(n < SwingLength * 2 + 5) return 0;
   ok = true;

   double sh = 0, sl = 0, v;
   bool   hh = false, hl = false;
   int    tr = 0;
   for(int i = 0; i < n; i++)
     {
      if(PivotHighAt(r, i, v)) { sh = v; hh = true; }
      if(PivotLowAt(r, i, v))  { sl = v; hl = true; }
      if(hh && r[i].close > sh) { tr =  1; hh = false; }
      if(hl && r[i].close < sl) { tr = -1; hl = false; }
     }
   return tr;
  }

int TrendOf(const int si, const int k)
  {
   string          sym  = g_symbols[si];
   ENUM_TIMEFRAMES tf   = TrendTf(k);
   int             slot = si * 5 + k;
   datetime        bt   = iTime(sym, tf, 0);
   if(bt != 0 && bt == g_trBar[slot]) return g_trVal[slot];

   bool ok;
   int  t = ComputeTrend(sym, tf, ok);
   if(!ok) return g_trVal[slot];
   g_trBar[slot] = bt;
   g_trVal[slot] = t;
   return t;
  }

//--- ตำแหน่ง x (พิกเซล) ของคอลัมน์ c เทียบจากต้นพื้นที่ที่เลื่อนได้
int ColX(const int c)
  {
   int x = 0;
   for(int i = 0; i < c; i++)
      x += ColW(i);
   return x;
  }

int TotalColsW() { return ColX(N_COLS); }

//+------------------------------------------------------------------+
//| Mouse wheel / ปุ่ม / คลิกแถว                                      |
//+------------------------------------------------------------------+
//--- กลุ่มใต้เมาส์: 1 = US, 2 = OTHER, 0 = ไม่มี
int GroupAt(const int x, const int y)
  {
   int xl = DashX - 8;
   int xr = xl + PANEL_W;
   if(x < xl || x > xr) return 0;
   if(y >= g_usTop && y <= g_usBot) return 1;
   if(y >= g_otTop && y <= g_otBot) return 2;
   return 0;
  }

void SetInside(const bool inside)
  {
   if(inside == g_inside) return;
   g_inside = inside;
   ChartSetInteger(0, CHART_MOUSE_SCROLL, inside ? false : g_origMouseScroll);
  }

void ScrollGroup(const int group, const int deltaRows)
  {
   if(group == 1) g_scrUs += deltaRows;
   else if(group == 2) g_scrOt += deltaRows;
   DrawDashboard();
  }

//--- เลื่อนแนวนอนแบบสมูท (ใช้ร่วมกันทั้งสองกรอบ) dir > 0 = ไปทางขวา; OnTimer ทำแอนิเมชันให้
void ScrollH(const int dir)
  {
   g_hTarget = MathMax(0.0, MathMin(g_hMax, g_hTarget + dir * HScrollPx));
   g_anim = true;
  }

//--- คลิก = เลือกแถว, ดับเบิลคลิก = เปิด/ปิดหน้าต่าง Advanced OB Dashboard (ไม่ส่งคำสั่งซื้อขาย)
void HandleClick(const int x, const int y)
  {
   // คลิกบนหน้าต่าง popup = ไม่ทำอะไร (กันคลิกทะลุไปโดนแถวด้านล่าง) รวมช่วงที่กำลังปิดอยู่
   if((g_detail || g_popT > 0.0) && x >= g_popX && x <= g_popX + POP_W && y >= g_popY && y <= g_popY + g_popH)
      return;

   int g = GroupAt(x, y);
   if(g == 0) return;

   int row0  = (g == 1) ? g_usRow0 : g_otRow0;
   int view  = (g == 1) ? g_viewUS : g_viewOT;
   int scr   = (g == 1) ? g_scrUs  : g_scrOt;
   int count = (g == 1) ? ArraySize(g_us) : ArraySize(g_ot);

   if(y < row0) return;
   int off = (y - row0) / ROW_H;
   if(off >= view) return;
   int idx = scr + off;
   if(idx >= count) return;

   string sym = (g == 1) ? g_us[idx].symbol : g_ot[idx].symbol;
   ulong  now = GetTickCount64();
   bool   dbl = (sym == g_lastClickSym && (now - g_lastClickMs) < 400);

   g_sel = sym;
   g_lastClickSym = sym;
   g_lastClickMs  = now;
   if(dbl)
     {
      if(g_detail && g_detailSym == sym)
        {
         g_detail  = false;                // ดับเบิลคลิกซ้ำที่ Symbol เดิม = ปิด (เล่นแอนิเมชันปิด)
         g_popAnim = true;
        }
      else
        {
         g_detail    = true;               // เปิด / สลับไป Symbol ใหม่
         g_detailSym = sym;
         PlacePopup(x, y);
         g_popAnim   = true;
        }
     }
   DrawDashboard();
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_MOUSE_MOVE)
     {
      SetInside(GroupAt((int)lparam, (int)dparam) > 0);
      return;
     }

   if(id == CHARTEVENT_MOUSE_WHEEL)
     {
      int x     = (int)(short)lparam;
      int y     = (int)(short)(lparam >> 16);
      int flags = (int)((lparam >> 32) & 0xFFFF);
      int g = GroupAt(x, y);
      SetInside(g > 0);
      if(g > 0)
        {
         if((flags & 0x0004) != 0)   // กด Shift ค้าง -> เลื่อนแนวนอนแบบสมูท
            ScrollH((dparam < 0) ? 1 : -1);
         else
            ScrollGroup(g, (dparam < 0) ? WheelStep : -WheelStep);
        }
      return;
     }

   if(id == CHARTEVENT_CLICK)
     {
      HandleClick((int)lparam, (int)dparam);
      return;
     }

   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      if(sparam == PFX + "pop_close")
        {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         g_detail  = false;
         g_popAnim = true;
         DrawDashboard();
         return;
        }
     }
  }

//+------------------------------------------------------------------+
void BuildSymbolList()
  {
   int total = SymbolsTotal(UseMarketWatchOnly);
   ArrayResize(g_symbols, total);
   ArrayResize(g_lastBar, total);
   ArrayResize(g_cache, total);
   ArrayResize(g_isUs, total);
   ArrayResize(g_trBar, total * 5);
   ArrayResize(g_trVal, total * 5);
   ArrayInitialize(g_trBar, 0);
   ArrayInitialize(g_trVal, 0);

   string parts[];
   int np = StringSplit(UsKeywords, ';', parts);
   ArrayResize(g_usKw, 0);
   for(int p = 0; p < np; p++)
     {
      string kw = parts[p];
      StringTrimLeft(kw);
      StringTrimRight(kw);
      StringToUpper(kw);
      if(kw == "") continue;
      int n = ArraySize(g_usKw);
      ArrayResize(g_usKw, n + 1);
      g_usKw[n] = kw;
     }

   int usCount = 0;
   for(int i = 0; i < total; i++)
     {
      g_symbols[i] = SymbolName(i, UseMarketWatchOnly);
      g_lastBar[i] = 0;
      g_isUs[i]    = IsUsStock(g_symbols[i]);
      if(g_isUs[i]) usCount++;
      if(i < 8)
         PrintFormat("  [%s] path='%s' exch='%s' country='%s' -> %s", g_symbols[i],
                     SymbolInfoString(g_symbols[i], SYMBOL_PATH),
                     SymbolInfoString(g_symbols[i], SYMBOL_EXCHANGE),
                     SymbolInfoString(g_symbols[i], SYMBOL_COUNTRY),
                     g_isUs[i] ? "US STOCK" : "OTHER");
     }
   PrintFormat("HQ Market Scanner: loaded %d symbols (%s), US stocks = %d, other = %d",
               total, EnumToString(g_tf), usCount, total - usCount);
  }

//+------------------------------------------------------------------+
bool IsUsStock(const string sym)
  {
   string path = SymbolInfoString(sym, SYMBOL_PATH);
   string exch = SymbolInfoString(sym, SYMBOL_EXCHANGE);
   string cty  = SymbolInfoString(sym, SYMBOL_COUNTRY);
   StringToUpper(path);
   StringToUpper(exch);
   StringToUpper(cty);

   if(RequireStockInPath)
     {
      if(StringFind(path, "STOCK") < 0 && StringFind(path, "SHARE") < 0 && StringFind(path, "EQUIT") < 0)
         return false;
     }

   string seg[];
   int ns = StringSplit(path, '\\', seg);

   for(int k = 0; k < ArraySize(g_usKw); k++)
     {
      string kw = g_usKw[k];
      for(int s = 0; s < ns; s++)
         if(seg[s] == kw) return true;
      if(exch != "" && (exch == kw || StringFind(exch, kw) >= 0)) return true;
      if(cty  != "" && (cty  == kw || StringFind(cty,  kw) >= 0)) return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
void ResetResult(ScanResult &r, const string sym)
  {
   r.symbol      = sym;
   r.digits      = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   r.pctValid    = false;
   r.price       = 0.0;
   r.openPrice   = 0.0;
   r.pct         = 0.0;
   r.hasOB       = false;
   r.dir         = 0;
   r.obHigh      = 0.0;
   r.obLow       = 0.0;
   r.confirmTime = 0;
   r.barsAgo     = 0;
   r.retested    = false;
   r.us          = false;
   r.score       = 0.0;
   r.grade       = "";
   r.atrX        = 0.0;
   r.widthX      = 0.0;
   r.bosX        = 0.0;
   r.fvgX        = 0.0;
   r.touches     = 0;
   for(int k = 0; k < 5; k++)
      r.trend[k] = 0;
  }

//+------------------------------------------------------------------+
double GetOpenPrice(const string sym)
  {
   if(OpenReference == OPEN_PREV_CLOSE)
     {
      double pc = iClose(sym, PERIOD_D1, 1);
      if(pc > 0.0) return pc;
      return iOpen(sym, PERIOD_D1, 0);
     }
   if(OpenReference == OPEN_DAILY)
      return iOpen(sym, PERIOD_D1, 0);
   if(OpenReference == OPEN_WEEKLY)
      return iOpen(sym, PERIOD_W1, 0);

   MqlRates h[];
   int n = CopyRates(sym, PERIOD_H1, 0, 300, h);
   if(n >= 2)
     {
      ArraySetAsSeries(h, false);
      long needDiff = (long)(SessionGapHours + 1) * 3600;
      for(int i = n - 1; i > 0; i--)
         if((long)(h[i].time - h[i-1].time) >= needDiff)
            return h[i].open;
     }
   return iOpen(sym, PERIOD_D1, 0);
  }

void CalcPctSinceOpen(ScanResult &r)
  {
   double refP  = GetOpenPrice(r.symbol);
   double price = SymbolInfoDouble(r.symbol, SYMBOL_BID);
   if(price <= 0.0) price = SymbolInfoDouble(r.symbol, SYMBOL_LAST);
   if(price <= 0.0) price = iClose(r.symbol, PERIOD_M1, 0);

   if(refP > 0.0 && price > 0.0)
     {
      r.openPrice = refP;
      r.price     = price;
      r.pct       = (price - refP) / refP * 100.0;
      r.pctValid  = true;
     }
  }

//+------------------------------------------------------------------+
//| helpers                                                          |
//+------------------------------------------------------------------+
void RemPend(PendC &a[], int k)
  {
   int n = ArraySize(a);
   for(int i = k; i < n - 1; i++)
      a[i] = a[i + 1];
   ArrayResize(a, n - 1);
  }

void AddPend(PendC &a[], double hi, double lo, int obBar, int dispBar, double sref, double fvgX)
  {
   int n = ArraySize(a);
   ArrayResize(a, n + 1);
   a[n].hi = hi;
   a[n].lo = lo;
   a[n].obBar = obBar;
   a[n].dispBar = dispBar;
   a[n].swingRef = sref;
   a[n].fvgX = fvgX;
  }

void AddOBI(OBI &a[], int dir, double hi, double lo, int bar, double atrX, double bosX,
            double fvgX, double widthX, int touches, double score)
  {
   int n = ArraySize(a);
   ArrayResize(a, n + 1);
   a[n].dir = dir;
   a[n].hi = hi;
   a[n].lo = lo;
   a[n].confirmBar = bar;
   a[n].mit = false;
   a[n].atrX = atrX;
   a[n].bosX = bosX;
   a[n].fvgX = fvgX;
   a[n].widthX = widthX;
   a[n].touches = touches;
   a[n].score = score;
  }

bool PivotHighAt(const MqlRates &r[], int i, double &val)
  {
   int c = i - SwingLength;
   if(c - SwingLength < 0) return false;
   double v = r[c].high;
   for(int k = 1; k <= SwingLength; k++)
     {
      if(!(v > r[c - k].high))  return false;
      if(!(v >= r[c + k].high)) return false;
     }
   val = v;
   return true;
  }

bool PivotLowAt(const MqlRates &r[], int i, double &val)
  {
   int c = i - SwingLength;
   if(c - SwingLength < 0) return false;
   double v = r[c].low;
   for(int k = 1; k <= SwingLength; k++)
     {
      if(!(v < r[c - k].low))  return false;
      if(!(v <= r[c + k].low)) return false;
     }
   val = v;
   return true;
  }

//+------------------------------------------------------------------+
//| Quality Score 0-100 + Grade (เหมือน calcScore / gradeOf ใน Pine)   |
//+------------------------------------------------------------------+
double CalcScore(const double strengthX, const double bosX, const double fvgX,
                 const double widthX, const int touches)
  {
   double sAtr   = MathMin(strengthX / AtrFullScore, 1.0);
   double sBos   = MathMin(bosX / BosIdealATR, 1.0);
   double sFvg   = MathMin(fvgX / FvgIdealATR, 1.0);
   double sBF    = 0.4 * sBos + 0.6 * sFvg;
   double sFresh = (touches == 0) ? 1.0 : ((touches == 1) ? 0.5 : 0.0);
   double wRange = MathMax(MaxWidthATR - IdealWidthATR, 0.01);
   double sW     = (widthX <= IdealWidthATR) ? 1.0
                   : ((widthX >= MaxWidthATR) ? 0.0 : 1.0 - (widthX - IdealWidthATR) / wRange);
   double wSum   = WeightAtr + WeightBosFvg + WeightFresh + WeightWidth;
   if(wSum <= 0.0) return 0.0;
   return 100.0 * (sAtr * WeightAtr + sBF * WeightBosFvg + sFresh * WeightFresh + sW * WeightWidth) / wSum;
  }

string GradeOf(const double s)
  {
   if(s >= 85.0) return "A+";
   if(s >= 70.0) return "A";
   if(s >= 55.0) return "B";
   return "C";
  }

//--- สีเกรดเหมือน Pine (A+ เขียว / A น้ำเงิน / B เหลืองอำพัน / C เทา)
color GradeColor(const string g)
  {
   if(g == "A+") return C'0,200,83';
   if(g == "A")  return C'41,98,255';
   if(g == "B")  return C'255,179,0';
   return C'158,158,158';
  }

//--- addOB ของ Pine: ผ่านเกณฑ์ ATR Strength / Width / Quality เท่านั้นถึงจะเป็น OB
void TryAddOB(OBI &obs[], const int dir, const double hi, const double lo, const int confirmBar,
              const double atrVal, const double strX, const double bosX, const double fvgX,
              const int touches)
  {
   double widthX = (atrVal > 0.0) ? (hi - lo) / atrVal : 0.0;
   double score  = CalcScore(strX, bosX, fvgX, widthX, touches);
   if(strX >= MinAtrShow && widthX <= MaxWidthATR && score >= MinQuality)
      AddOBI(obs, dir, hi, lo, confirmBar, strX, bosX, fvgX, widthX, touches, score);
  }

//+------------------------------------------------------------------+
//| หา OB ล่าสุด (ตรรกะเดียวกับ Pine "ORDER BLOCK QUALITY" / HQ-OB-Q)   |
//|  OB Origin -> ATR Strength -> BOS + FVG -> Unmitigated ->          |
//|  OB Width/ATR -> Quality Score                                     |
//+------------------------------------------------------------------+
bool ScanSymbolLatestOB(const string sym, ScanResult &res)
  {
   res.hasOB = false;

   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   int size = CopyRates(sym, g_tf, 1, LookbackBars, rates);
   if(size < SwingLength * 2 + AtrLength + 5) return(false);

   double structHigh = 0, structLow = 0;
   bool   hasHigh = false, hasLow = false;
   double atrSum = 0, atrPrev = 0;

   PendC pBull[], pBear[];
   OBI   obs[];

   for(int i = 0; i < size; i++)
     {
      //--- ATR (RMA)
      double tr = (i == 0) ? (rates[i].high - rates[i].low)
                  : MathMax(rates[i].high - rates[i].low,
                            MathMax(MathAbs(rates[i].high - rates[i-1].close),
                                    MathAbs(rates[i].low  - rates[i-1].close)));
      double atrVal = 0;
      if(i < AtrLength - 1)
         atrSum += tr;
      else if(i == AtrLength - 1)
        {
         atrPrev = (atrSum + tr) / AtrLength;
         atrVal = atrPrev;
        }
      else
        {
         atrPrev = (atrPrev * (AtrLength - 1) + tr) / AtrLength;
         atrVal = atrPrev;
        }

      //--- Swing structure: ใช้ Pivot ล่าสุดตรงๆ เหมือน Pine
      double v;
      if(PivotHighAt(rates, i, v)) { structHigh = v; hasHigh = true; }
      if(PivotLowAt(rates, i, v))  { structLow  = v; hasLow  = true; }

      //--- Displacement
      double body = MathAbs(rates[i].close - rates[i].open);
      bool   passATR = (atrVal > 0.0) && (body / atrVal >= MinDispStrength);

      bool isBullDisp = passATR && rates[i].close > rates[i].open;
      bool isBearDisp = passATR && rates[i].close < rates[i].open;

      //--- STEP 1: Displacement + FVG -> Pending Candidate
      if(isBullDisp && hasHigh)
        {
         int originIdx = -1;
         for(int k = 1; k <= 10; k++)
           {
            if(i - k < 0) break;
            if(rates[i-k].close < rates[i-k].open) { originIdx = k; break; }
           }
         if(originIdx >= 0)
           {
            double fvgMax = 0.0;
            for(int j = 0; j <= MaxObToFvgDistance; j++)
              {
               int idx = i - j;
               if(idx - 2 < 0) break;
               double g = rates[idx].low - rates[idx-2].high;
               if(g > 0.0) fvgMax = MathMax(fvgMax, g);
              }
            if(fvgMax > 0.0)
               AddPend(pBull, rates[i-originIdx].high, rates[i-originIdx].low,
                       i - originIdx, i, structHigh, fvgMax / atrVal);
           }
        }

      if(isBearDisp && hasLow)
        {
         int originIdx = -1;
         for(int k = 1; k <= 10; k++)
           {
            if(i - k < 0) break;
            if(rates[i-k].close > rates[i-k].open) { originIdx = k; break; }
           }
         if(originIdx >= 0)
           {
            double fvgMax = 0.0;
            for(int j = 0; j <= MaxObToFvgDistance; j++)
              {
               int idx = i - j;
               if(idx - 2 < 0) break;
               double g = rates[idx-2].low - rates[idx].high;
               if(g > 0.0) fvgMax = MathMax(fvgMax, g);
              }
            if(fvgMax > 0.0)
               AddPend(pBear, rates[i-originIdx].high, rates[i-originIdx].low,
                       i - originIdx, i, structLow, fvgMax / atrVal);
           }
        }

      //--- STEP 2: BOS confirmation (Bullish)
      for(int k = ArraySize(pBull) - 1; k >= 0; k--)
        {
         if(i - pBull[k].dispBar > MaxCandidateAge)
            RemPend(pBull, k);
         else if(rates[i].close < pBull[k].lo)
            RemPend(pBull, k);
         else if(rates[i].close > pBull[k].swingRef && i > pBull[k].dispBar)
           {
            // ATR Strength: จาก High สูงสุดนับตั้งแต่แท่ง OB จนถึงตอนยืนยัน
            double extremeHigh = rates[i].high;
            for(int q = 0; q <= i - pBull[k].obBar; q++)
               extremeHigh = MathMax(extremeHigh, rates[i - q].high);
            double strX = (atrVal > 0.0) ? (extremeHigh - pBull[k].lo) / atrVal : 0.0;

            // Unmitigated: นับแท่งที่แตะโซนหลัง Displacement จนถึงตอนยืนยัน
            int touches = 0;
            for(int q = 0; q <= i - pBull[k].dispBar - 1; q++)
               if(rates[i - q].low <= pBull[k].hi) touches++;

            double bosX = (atrVal > 0.0) ? (rates[i].close - pBull[k].swingRef) / atrVal : 0.0;
            TryAddOB(obs, 1, pBull[k].hi, pBull[k].lo, i, atrVal, strX, bosX, pBull[k].fvgX, touches);
            RemPend(pBull, k);
           }
        }

      //--- STEP 2: BOS confirmation (Bearish)
      for(int k = ArraySize(pBear) - 1; k >= 0; k--)
        {
         if(i - pBear[k].dispBar > MaxCandidateAge)
            RemPend(pBear, k);
         else if(rates[i].close > pBear[k].hi)
            RemPend(pBear, k);
         else if(rates[i].close < pBear[k].swingRef && i > pBear[k].dispBar)
           {
            double extremeLow = rates[i].low;
            for(int q = 0; q <= i - pBear[k].obBar; q++)
               extremeLow = MathMin(extremeLow, rates[i - q].low);
            double strX = (atrVal > 0.0) ? (pBear[k].hi - extremeLow) / atrVal : 0.0;

            int touches = 0;
            for(int q = 0; q <= i - pBear[k].dispBar - 1; q++)
               if(rates[i - q].high >= pBear[k].lo) touches++;

            double bosX = (atrVal > 0.0) ? (pBear[k].swingRef - rates[i].close) / atrVal : 0.0;
            TryAddOB(obs, -1, pBear[k].hi, pBear[k].lo, i, atrVal, strX, bosX, pBear[k].fvgX, touches);
            RemPend(pBear, k);
           }
        }

      //--- STEP 3: Mitigation / อัปเดต Freshness + Quality Score
      for(int m = 0; m < ArraySize(obs); m++)
        {
         if(obs[m].mit) continue;
         double obH = obs[m].hi, obL = obs[m].lo;
         bool isMit = false;
         if(obs[m].dir == 1)
           {
            if(MitigationMethod == WICK_TOUCH)            isMit = rates[i].low <= obH;
            else if(MitigationMethod == CLOSE_INSIDE_OB)  isMit = rates[i].close <= obH && rates[i].close >= obL;
            else                                          isMit = rates[i].open > obH && rates[i].close < obL;
           }
         else
           {
            if(MitigationMethod == WICK_TOUCH)            isMit = rates[i].high >= obL;
            else if(MitigationMethod == CLOSE_INSIDE_OB)  isMit = rates[i].close >= obL && rates[i].close <= obH;
            else                                          isMit = rates[i].open < obL && rates[i].close > obH;
           }

         if(isMit)
           {
            obs[m].mit = true;
            continue;
           }

         // แตะโซนแต่ยังไม่ Mitigate -> ลดคะแนน Freshness
         bool touched = (obs[m].dir == 1) ? (rates[i].low <= obH) : (rates[i].high >= obL);
         if(touched)
           {
            obs[m].touches++;
            obs[m].score = CalcScore(obs[m].atrX, obs[m].bosX, obs[m].fvgX, obs[m].widthX, obs[m].touches);
           }
        }
     }

   //--- เลือก OB ล่าสุด (ถ้า ShowMitigatedOB = false ข้าม OB ที่ Mitigate แล้ว)
   int L = -1;
   for(int m = ArraySize(obs) - 1; m >= 0; m--)
      if(ShowMitigatedOB || !obs[m].mit) { L = m; break; }
   if(L < 0) return(true);

   res.hasOB       = true;
   res.dir         = obs[L].dir;
   res.obHigh      = obs[L].hi;
   res.obLow       = obs[L].lo;
   res.retested    = obs[L].mit;
   res.confirmTime = rates[obs[L].confirmBar].time;
   res.barsAgo     = (size - 1) - obs[L].confirmBar;
   res.score       = obs[L].score;
   res.grade       = GradeOf(obs[L].score);
   res.atrX        = obs[L].atrX;
   res.widthX      = obs[L].widthX;
   res.bosX        = obs[L].bosX;
   res.fvgX        = obs[L].fvgX;
   res.touches     = obs[L].touches;
   return(true);
  }

//+------------------------------------------------------------------+
int ObRank(const ScanResult &r)
  {
   if(!r.hasOB) return 0;
   return r.retested ? 1 : 2;
  }

bool ShouldSwap(const ScanResult &a, const ScanResult &b)
  {
   if(!a.pctValid && b.pctValid) return true;
   if(a.pctValid && !b.pctValid) return false;

   switch(SortMode)
     {
      case SORT_PCT_DESC:
         return (b.pct > a.pct);
      case SORT_ABS_PCT_DESC:
         return (MathAbs(b.pct) > MathAbs(a.pct));
      case SORT_OB_FIRST:
        {
         int ra = ObRank(a), rb = ObRank(b);
         if(ra != rb) return (rb > ra);
         if(ra > 0 && b.confirmTime != a.confirmTime) return (b.confirmTime > a.confirmTime);
         return (MathAbs(b.pct) > MathAbs(a.pct));
        }
      default:
         return false;
     }
   return false;
  }

//+------------------------------------------------------------------+
void ScanAndDraw()
  {
   int total = ArraySize(g_symbols);
   ScanResult results[];
   int found = 0;
   int withOB = 0;

   for(int i = 0; i < total; i++)
     {
      ScanResult r;
      ResetResult(r, g_symbols[i]);

      datetime bt = iTime(g_symbols[i], g_tf, 0);
      if(bt != 0 && bt == g_lastBar[i])
         r = g_cache[i];
      else if(ScanSymbolLatestOB(g_symbols[i], r))
        {
         g_cache[i]   = r;
         g_lastBar[i] = bt;
        }
      //--- Trend แต่ละ Time frame
      for(int k = 0; k < 5; k++)
         r.trend[k] = TrendOf(i, k);
      CalcPctSinceOpen(r);
      r.us = g_isUs[i];

      if(r.hasOB) withOB++;

      if(!ShowAllSymbols)
        {
         if(!r.hasOB) continue;
         if(ShowOnlyNotRetested && r.retested) continue;
        }

      ArrayResize(results, found+1);
      results[found] = r;
      found++;
     }

   if(SortMode != SORT_MARKET_WATCH)
     {
      for(int a = 0; a < found-1; a++)
         for(int b = a+1; b < found; b++)
            if(ShouldSwap(results[a], results[b]))
              {
               ScanResult tmp = results[a]; results[a] = results[b]; results[b] = tmp;
              }
     }

   //--- แยกกลุ่ม US / อื่นๆ (คงลำดับที่เรียงแล้ว)
   ArrayResize(g_us, 0);
   ArrayResize(g_ot, 0);
   for(int k = 0; k < found; k++)
     {
      if(results[k].us)
        {
         int n = ArraySize(g_us);
         ArrayResize(g_us, n + 1);
         g_us[n] = results[k];
        }
      else
        {
         int n = ArraySize(g_ot);
         ArrayResize(g_ot, n + 1);
         g_ot[n] = results[k];
        }
     }

   g_found  = found;
   g_withOB = withOB;
   DrawDashboard();
  }

//+------------------------------------------------------------------+
//| UI (อ่านค่าจาก ScanResult เท่านั้น)                               |
//+------------------------------------------------------------------+
string OpenRefText()
  {
   if(OpenReference == OPEN_PREV_CLOSE) return "Prev Close";
   if(OpenReference == OPEN_DAILY)      return "Daily Open";
   if(OpenReference == OPEN_WEEKLY)     return "Weekly Open";
   return "Session Open";
  }

string TfText(const ENUM_TIMEFRAMES tf)
  {
   string s = EnumToString(tf);
   if(StringFind(s, "PERIOD_") == 0) s = StringSubstr(s, 7);
   return s;
  }

string ShortSym(const string s)
  {
   return (StringLen(s) > 10) ? StringSubstr(s, 0, 9) + "~" : s;
  }

string Fmt(const double v, const int digits)
  {
   return DoubleToString(v, digits);
  }

//--- primitives
void SetLbl(const string name, const string text, const int x, const int y, const color clr,
            const int size, const bool bold, const ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER)
  {
   string full = PFX + name;
   if(ObjectFind(0, full) < 0) ObjectCreate(0, full, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, full, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, full, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, full, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, full, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, full, OBJPROP_TEXT, text);
   ObjectSetInteger(0, full, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, full, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, full, OBJPROP_FONT, bold ? FontName + " Bold" : FontName);
   ObjectSetInteger(0, full, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, full, OBJPROP_HIDDEN, true);
  }

void SetRect(const string name, const int x, const int y, const int w, const int h,
             const color bg, const color border)
  {
   string full = PFX + name;
   if(ObjectFind(0, full) < 0) ObjectCreate(0, full, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, full, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, full, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, full, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, full, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, full, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, full, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, full, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, full, OBJPROP_COLOR, border);
   ObjectSetInteger(0, full, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, full, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, full, OBJPROP_HIDDEN, true);
  }

void SetButton(const string name, const string text, const int x, const int y)
  {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, 22);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, 15);
   ObjectSetString(0,  name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_COLOR, C_HDR);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C'20,20,20');
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, FrameColor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 10);
  }

//--- วางเซลล์แบบเลื่อนเป็นพิกเซล: ตัดตัวอักษรที่ล้นขอบซ้าย/ขวาของพื้นที่เลื่อน (Consolas = ฟอนต์ความกว้างคงที่)
void PlaceScrollCell(const string name, const string text, const int cellX, const int w, const bool right,
                     const int y, const color clr, const int size, const bool bold)
  {
   string full = PFX + name;
   int    len  = StringLen(text);
   int    x0   = right ? cellX + w - 10 - (int)MathRound(len * CharPx) : cellX;
   int    vl   = DashX + SYM_W;            // ขอบซ้ายของพื้นที่เลื่อน (ต่อจากคอลัมน์ SYMBOL)
   int    vr   = DashX + SYM_W + VIEW_W;   // ขอบขวา
   string t    = text;

   if(x0 < vl)
     {
      int k = (int)MathCeil((vl - x0) / CharPx);
      if(k >= len) { ObjectDelete(0, full); return; }
      t   = StringSubstr(t, k);
      x0 += (int)MathRound(k * CharPx);
     }

   int n = (int)MathFloor((vr - x0) / CharPx);
   if(n <= 0) { ObjectDelete(0, full); return; }
   if(n < StringLen(t)) t = StringSubstr(t, 0, n);

   SetLbl(name, t, x0, y, clr, size, bold, ANCHOR_LEFT_UPPER);
  }

//--- ข้อความ + สี ของคอลัมน์ที่เลื่อนได้ 1 ช่อง
void CellOf(const ScanResult &r, const int c, string &txt, color &clr)
  {
   txt = "—";
   clr = C_MUTED;

   switch(c)
     {
      case 0:   // PRICE
         if(r.pctValid) { txt = Fmt(r.price, r.digits); clr = C_HDR; }
         else           { txt = "n/a"; }
         return;
      case 1:   // % CHG
         if(r.pctValid)
           {
            txt = (r.pct >= 0 ? "+" : "") + DoubleToString(r.pct, 2) + "%";
            clr = (r.pct > 0) ? C_GREEN : (r.pct < 0 ? C_RED : C_HDR);
           }
         else txt = "n/a";
         return;
      case 2:   // LATEST OB + GRADE
         if(r.hasOB)
           {
            txt = string(r.dir == 1 ? "BULL OB" : "BEAR OB") + " " + r.grade;
            clr = (r.dir == 1) ? C_GREEN : C_RED;
           }
         return;
      case 3:   // OB ZONE (Bull = เขียว / Bear = แดง)
         if(r.hasOB)
           {
            txt = Fmt(r.obHigh, r.digits) + " / " + Fmt(r.obLow, r.digits);
            clr = (r.dir == 1) ? C_GREEN : C_RED;
           }
         return;
      case 4:   // STATUS
         if(r.hasOB)
           {
            txt = r.retested ? "Retested" : "NOT Retested";
            clr = r.retested ? C_MUTED : C_YELLOW;
           }
         return;
      case 5: case 6: case 7: case 8: case 9:   // TREND 1D, 1H, 30M, 15M, 1M
         if(r.trend[c - 5] == 1)       { txt = "BULL"; clr = C_GREEN; }
         else if(r.trend[c - 5] == -1) { txt = "BEAR"; clr = C_RED; }
         return;
     }
  }

void DrawRow(const string id, const ScanResult &r, const int y)
  {
   const int F = 9;

   if(r.symbol == g_sel)
      SetRect("row_sel_" + id, DashX - 6, y - 1, PANEL_W - 4, ROW_H, C_SELBG, C_SELBG);

   // คอลัมน์ที่ตรึงไว้
   SetLbl("row_sym_" + id, ShortSym(r.symbol), DashX, y, C_HDR, F, false);

   // คอลัมน์ที่เลื่อนได้ (เลื่อนเป็นพิกเซล + ตัดข้อความที่ล้นขอบ)
   for(int c = 0; c < N_COLS; c++)
     {
      string txt;
      color  clr;
      CellOf(r, c, txt, clr);
      PlaceScrollCell("row_c" + IntegerToString(c) + "_" + id, txt, DashX + SYM_W + ColX(c) - (int)g_hOff,
                      ColW(c), ColRight(c), y, clr, F, false);
     }
  }

int SectionHeight(const int view) { return 42 + view * ROW_H + 6; }

//--- วาด 1 กรอบ คืนค่า y ด้านล่างของกรอบ
int DrawSection(const string tag, const string title, ScanResult &arr[], const int count,
                int &scr, const int view, const int y0)
  {
   const int F = 9;
   int maxScr = MathMax(0, count - view);
   if(scr > maxScr) scr = maxScr;
   if(scr < 0)      scr = 0;

   SetRect("sep_" + tag, DashX - 8, y0, PANEL_W, 1, FrameColor, FrameColor);

   SetLbl("hdr_" + tag + "_title", title, DashX, y0 + 5, FrameColor, 10, true);

   // แถวหัวตาราง: SYMBOL (ตรึง) + คอลัมน์ที่มองเห็น
   int hy = y0 + 24;
   SetLbl("hdr_" + tag + "_sym", "SYMBOL", DashX, hy, C_HDR, F, true);
   for(int c = 0; c < N_COLS; c++)
      PlaceScrollCell("hdr_" + tag + "_c" + IntegerToString(c), ColHdr(c),
                      DashX + SYM_W + ColX(c) - (int)g_hOff, ColW(c), ColRight(c), hy, C_HDR, F, true);
   SetRect("hdr_" + tag + "_ln", DashX - 6, y0 + 39, PANEL_W - 4, 1, C'45,45,45', C'45,45,45');

   int row0 = y0 + 42;
   if(count == 0)
     {
      SetLbl("row_" + tag + "_none", "-- no symbols in this group --", DashX, row0, C_MUTED, F, false);
      return y0 + SectionHeight(view);
     }

   int last = MathMin(scr + view, count);
   for(int i = scr; i < last; i++)
      DrawRow(tag + "_" + IntegerToString(i), arr[i], row0 + (i - scr) * ROW_H);

   return y0 + SectionHeight(view);
  }

bool FindRow(const string sym, ScanResult &out)
  {
   for(int i = 0; i < ArraySize(g_us); i++)
      if(g_us[i].symbol == sym) { out = g_us[i]; return true; }
   for(int i = 0; i < ArraySize(g_ot); i++)
      if(g_ot[i].symbol == sym) { out = g_ot[i]; return true; }
   return false;
  }

//--- ตำแหน่งหน้าต่าง: ชิดขวาของแผงถ้ามีที่ว่าง ไม่งั้นวางใกล้เมาส์ (ไม่ให้ล้นกราฟ)
void PlacePopup(const int cx, const int cy)
  {
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

   int x = DashX - 8 + PANEL_W + 8;
   int y = cy - 24;
   if(x + POP_W > cw - 4)
     {
      x = cx + 16;
      y = cy + 12;
      if(x + POP_W > cw - 4) x = cx - POP_W - 16;
     }
   if(y + POP_H > ch - 4) y = ch - POP_H - 4;
   if(x < 4) x = 4;
   if(y < 4) y = 4;
   g_popX = x;
   g_popY = y;
  }

//--- แถวสถานะแบบ pill (BOS / FVG / Mitigation) - สี Fade ตามแอนิเมชัน
void DrawPill(const string id, const string label, const string value, const int x, const int y,
              const color txt, const color bg)
  {
   SetLbl("pop_" + id + "_l", label, x, y, PC(C_HDR), 9, false);
   int pw = StringLen(value) * 6 + 14;
   SetRect("pop_" + id + "_bg", x + 88, y - 1, pw, 17, PC(bg), PC(bg));
   SetLbl("pop_" + id + "_v", value, x + 88 + 7, y + 1, PC(txt), 8, true);
  }

//--- หน้าต่าง Advanced OB Dashboard (ดับเบิลคลิกที่ Symbol) - แสดงข้อมูลวิเคราะห์เท่านั้น ไม่มีคำสั่งซื้อขาย
//--- มีแอนิเมชัน: Fade จากสีพื้นกราฟ + เลื่อนขึ้น 14px (ease-out cubic)
void DrawPopup()
  {
   // ปิดสนิทแล้ว (และไม่ได้ถูกสั่งเปิด) -> ลบ object ทิ้ง
   if(!g_detail && g_popT <= 0.0)
     {
      ObjectsDeleteAll(0, PFX + "pop_");
      return;
     }

   ScanResult w;
   if(!FindRow(g_detailSym, w))
     {
      g_detail  = false;
      g_popT    = 0.0;
      g_popAnim = false;
      ObjectsDeleteAll(0, PFX + "pop_");
      return;
     }

   // ระหว่างแอนิเมชัน (g_light) ไม่ลบทิ้ง แค่อัปเดต object เดิม จะได้ไม่กะพริบ
   if(!g_light) ObjectsDeleteAll(0, PFX + "pop_");

   g_pe  = 1.0 - MathPow(1.0 - g_popT, 3.0);                     // ease-out cubic
   g_pbg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);

   const color C_POPBORDER = C'55,55,55';
   const color C_OKTXT     = C'0,200,83';
   const color C_OKBG      = C'10,50,28';

   int x = g_popX;
   int y = g_popY + (int)MathRound((1.0 - g_pe) * 14.0);          // เลื่อนขึ้นจากด้านล่าง 14px
   g_popH = w.hasOB ? POP_H : 78;

   SetRect("pop_bg", x, y, POP_W, g_popH, PC(C'0,0,0'), PC(C_POPBORDER));
   SetLbl("pop_title", "Advanced OB Dashboard", x + 12, y + 10, PC(C_HDR), 11, true);

   string btn = PFX + "pop_close";
   SetButton(btn, "X", x + POP_W - 30, y + 9);
   ObjectSetInteger(0, btn, OBJPROP_COLOR,        PC(C_HDR));
   ObjectSetInteger(0, btn, OBJPROP_BGCOLOR,      PC(C'20,20,20'));
   ObjectSetInteger(0, btn, OBJPROP_BORDER_COLOR, PC(FrameColor));

   string info = ShortSym(w.symbol);
   if(w.hasOB) info += "  " + string(w.dir == 1 ? "BULL" : "BEAR") + "  " + TfText(g_tf);
   SetLbl("pop_info", info, x + POP_W - 38, y + 13,
          PC(w.hasOB ? ((w.dir == 1) ? C_GREEN : C_RED) : C_MUTED), 8, false, ANCHOR_RIGHT_UPPER);

   if(!w.hasOB)
     {
      SetLbl("pop_none", "No qualified Order Block for this symbol", x + 14, y + 42, PC(C_MUTED), 9, false);
      return;
     }

   int c1 = x + 14, c2 = x + 200;
   SetLbl("pop_k1", "OB Grade",      c1, y + 36, PC(C_HDR), 9, true);
   SetLbl("pop_v1", w.grade,         c1, y + 52, PC(GradeColor(w.grade)), 13, true);
   SetLbl("pop_k2", "Quality Score", c2, y + 36, PC(C_HDR), 9, true);
   SetLbl("pop_v2", DoubleToString(w.score, 0) + "/100", c2, y + 52, PC(clrWhite), 13, true);

   SetLbl("pop_k3", "ATR Strength",  c1, y + 82, PC(C_HDR), 9, true);
   SetLbl("pop_v3", DoubleToString(w.atrX, 1) + "x",   c1, y + 98, PC(clrWhite), 13, true);
   SetLbl("pop_k4", "OB Width",      c2, y + 82, PC(C_HDR), 9, true);
   SetLbl("pop_v4", DoubleToString(w.widthX, 1) + "x", c2, y + 98, PC(clrWhite), 13, true);

   SetRect("pop_div", x + 10, y + 128, POP_W - 20, 1, PC(C'30,30,30'), PC(C'30,30,30'));

   // BOS / FVG ผ่านเสมอ (เป็นเงื่อนไขของการเป็น OB) ส่วน Mitigation ขึ้นกับสถานะจริง
   DrawPill("bos", "BOS", "Confirmed", x + 10, y + 138, C_OKTXT, C_OKBG);
   DrawPill("fvg", "FVG", "Detected",  x + 10, y + 158, C_OKTXT, C_OKBG);

   string mt;
   color  mtC, mtB;
   if(w.retested)          { mt = "Mitigated";                             mtC = C_RED;    mtB = C'60,15,15'; }
   else if(w.touches > 0)  { mt = "Touched x" + IntegerToString(w.touches); mtC = C_YELLOW; mtB = C'55,45,0'; }
   else                    { mt = "Fresh";                                 mtC = C_OKTXT;  mtB = C_OKBG; }
   DrawPill("mit", "Mitigation", mt, x + 10, y + 178, mtC, mtB);
  }

void DrawDashboard()
  {
   if(!g_light)
     {
      ObjectsDeleteAll(0, PFX + "row_");
      ObjectsDeleteAll(0, PFX + "hdr_");
     }

   // สร้างกรอบนอกก่อน เพื่อให้อยู่ใต้ object อื่นทั้งหมด (ปรับขนาดตอนท้าย)
   if(ObjectFind(0, PFX + "frame") < 0)
      SetRect("frame", DashX - 8, DashY - 8, PANEL_W, 10, C_BG, FrameColor);

   g_viewUS = MathMax(1, ViewRowsUS);
   g_viewOT = MathMax(1, ViewRowsOther);

   // ช่วงเลื่อนแนวนอน (พิกเซล)
   g_hMax = MathMax(0.0, (double)TotalColsW() - VIEW_W);
   if(g_hTarget > g_hMax) g_hTarget = g_hMax;
   if(g_hTarget < 0)      g_hTarget = 0;
   if(g_hOff > g_hMax)    g_hOff = g_hMax;
   if(g_hOff < 0)         g_hOff = 0;

   // ส่วนหัว
   SetLbl("hdr_title",    "MARKET SCANNER", DashX, DashY, C_HDR, 12, true);
   SetLbl("hdr_subtitle", "Order Block " + TfText(g_tf), DashX, DashY + 20, C_MUTED, 9, false);
   string colTxt = (g_hMax > 0) ? " | Shift+Wheel = scroll" : "";
   SetLbl("hdr_stats", "% vs " + OpenRefText() + " | " + IntegerToString(g_found) + " sym, " +
          IntegerToString(g_withOB) + " OB" + colTxt,
          DashX + PANEL_W - 16, DashY + 4, C_MUTED, 8, false, ANCHOR_RIGHT_UPPER);

   g_usTop  = DashY + 38;
   g_usBot  = g_usTop + SectionHeight(g_viewUS);
   g_usRow0 = g_usTop + 42;
   g_otTop  = g_usBot;
   g_otBot  = g_otTop + SectionHeight(g_viewOT);
   g_otRow0 = g_otTop + 42;

   int bottom = DrawSection("us", "US Stock", g_us, ArraySize(g_us), g_scrUs, g_viewUS, g_usTop);
   bottom     = DrawSection("ot", "Other",     g_ot, ArraySize(g_ot), g_scrOt, g_viewOT, g_otTop);
   // กรอบนอก
   SetRect("frame", DashX - 8, DashY - 8, PANEL_W, bottom - (DashY - 8) + 2, C_BG, FrameColor);

   // หน้าต่าง Advanced OB Dashboard (ดับเบิลคลิก) - วาดหลังสุดให้อยู่บนสุด
   DrawPopup();

   ChartRedraw();
  }
//+------------------------------------------------------------------+
