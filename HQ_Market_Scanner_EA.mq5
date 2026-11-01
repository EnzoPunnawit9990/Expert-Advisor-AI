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
//+------------------------------------------------------------------+
#property copyright "HQ-OB MT5 Scanner"
#property version   "2.05"

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

input group "Structure (BOS)  [เหมือนอินดิเคเตอร์]"
input int    SwingLength                 = 5;
input int    MaxCandidateAge             = 50;
input int    SwingQualifyAge             = 50;    // Swing ที่ยังไม่ผ่านเกณฑ์คุณภาพ รอได้นานสุดกี่แท่งนับจาก Pivot

input group "Displacement / ATR Quality Filter"
input int    AtrLength                   = 14;
input double MinDispStrength             = 1.0;   // OB ผ่านเมื่อ |close-open| >= ค่านี้ x ATR

input group "Imbalance (FVG)"
input int    MaxObToFvgDistance          = 3;

input group "Mitigation"
input ENUM_MITIGATION_METHOD MitigationMethod = CLOSE_INSIDE_OB;

input group "Auto Fibonacci (ใช้ Qualified Swing เท่านั้น)"
input ENUM_TIMEFRAMES FibTimeframe       = PERIOD_M5; // TF ที่ใช้หา Swing + กาง Fibo (ไม่ขึ้นกับ TF ของกราฟ)
input int    FibLookbackBars             = 1500;      // จำนวนแท่ง M5 ที่ใช้สแกน
input double FibMinLegATR                = 1.5;       // ขา Impulse ต้องยาวอย่างน้อยกี่ x ATR (กัน Swing เล็กๆ)
input double FibGoldenUpper              = 0.618;     // ขอบ Golden Zone ที่ 1
input double FibGoldenLower              = 0.786;     // ขอบ Golden Zone ที่ 2
input bool   DrawFibOnChart              = true;      // กาง OBJ_FIBO บนกราฟปัจจุบัน
input color  FibColor                    = clrDarkGray; // สีเส้น Fibo
input color  FibGoldenColor              = clrGold;     // สีเส้น Golden Zone

input group "Dashboard"
input bool   ShowAllSymbols              = true;   // true = แสดงทุก symbol, false = เฉพาะที่มี OB
input bool   ShowOnlyNotRetested         = false;  // (ShowAllSymbols=false) เฉพาะ OB ที่ยังไม่ Retest
input ENUM_HQ_SORT SortMode              = SORT_PCT_DESC;
input int    ViewRowsUS                  = 12;     // จำนวนแถวสูงสุดที่เห็นในกรอบ US (เกินนี้เลื่อนได้)
input int    ViewRowsOther               = 10;     // จำนวนแถวสูงสุดที่เห็นในกรอบอื่นๆ
input int    WheelStep                   = 3;      // เลื่อนแนวตั้งต่อ 1 notch / 1 คลิกปุ่ม ▲▼ (แถว)
input int    HColStep                    = 1;      // เลื่อนแนวนอนต่อ 1 notch (Shift+wheel) / 1 คลิกปุ่ม ◄ ► (คอลัมน์)
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
datetime g_lastBarFib[];
ENUM_TIMEFRAMES g_tf;
string   PFX = "HQOBS_";

struct FibInfo
  {
   bool     ok;
   int      dir;        // 1 = Bullish (Low->High), -1 = Bearish (High->Low)
   double   pA;         // จุดเริ่ม Impulse (Qualified Swing)
   double   pB;         // จุดจบ Impulse   (Qualified Swing)
   datetime tA;
   datetime tB;
   double   gzLo;       // Golden Zone ต่ำ
   double   gzHi;       // Golden Zone สูง
  };

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
   bool     retested;
   bool     us;           // true = หุ้นอเมริกา
   FibInfo  fib;          // Fibonacci / Golden Zone (M5)
  };

ScanResult g_cache[];
FibInfo    g_fibCache[];

//--- Dashboard state
#define ROW_H    16
#define N_COLS   6                        // PRICE, % CHG, LATEST OB, OB ZONE, STATUS, GOLDEN ZONE
#define SYM_W    90                       // ความกว้างคอลัมน์ SYMBOL (ตรึง)
#define PANEL_W  780
#define VIEW_W   (PANEL_W - 16 - SYM_W)   // ความกว้างพื้นที่คอลัมน์ที่เลื่อนได้

ScanResult g_us[], g_ot[];          // รายการที่แยกกลุ่มแล้ว (เรียงตาม SortMode)
bool       g_isUs[];
string     g_usKw[];
int        g_scrUs = 0, g_scrOt = 0;
int        g_colScr = 0, g_colMax = 0, g_colFirst = 0, g_colLast = N_COLS;
bool       g_origMouseScroll = true;
bool       g_origEvMove = false, g_origEvWheel = true;
bool       g_inside = false;
int        g_found = 0, g_withOB = 0;
int        g_usTop = 0, g_usBot = 0, g_otTop = 0, g_otBot = 0;
int        g_usRow0 = 0, g_otRow0 = 0, g_viewUS = 1, g_viewOT = 1;

string     g_sel = "";
bool       g_detail = false;
string     g_lastClickSym = "";
ulong      g_lastClickMs = 0;

color C_BG     = C'5,5,5';
color C_HDR    = C'215,215,215';
color C_MUTED  = C'125,125,125';
color C_GREEN  = C'0,230,90';
color C_RED    = C'255,60,60';
color C_YELLOW = C'255,215,0';
color C_GOLD   = C'255,190,40';
color C_SELBG  = C'18,40,62';

//--- Fibo object state
datetime   g_fibTA = 0, g_fibTB = 0;
double     g_fibPA = 0, g_fibPB = 0;

struct PendC
  {
   double hi, lo;
   int    dispBar;
   double swingRef;
  };

struct OBI
  {
   int    dir;
   double hi, lo;
   int    confirmBar;
   bool   mit;
  };

struct SwingC            // Swing ที่ตรวจพบ แต่ยังไม่ผ่านเกณฑ์คุณภาพ
  {
   double price;
   int    bar;
   int    scanned;
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
   EventSetTimer(RefreshSeconds);
   ScanAndDraw();
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
void OnTimer() { ScanAndDraw(); }

//+------------------------------------------------------------------+
//| COLUMN LAYOUT (SYMBOL ตรึง, คอลัมน์อื่นเลื่อนแนวนอนได้)             |
//|   0 PRICE  1 % CHG  2 LATEST OB  3 OB ZONE  4 STATUS  5 GOLDEN ZONE |
//+------------------------------------------------------------------+
int ColW(const int c)
  {
   switch(c)
     {
      case 0: return 80;    // PRICE
      case 1: return 80;    // % CHG
      case 2: return 90;    // LATEST OB
      case 3: return 160;   // OB ZONE
      case 4: return 105;   // STATUS
      case 5: return 156;   // GOLDEN ZONE
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
      case 5: return "GOLDEN ZONE";
     }
   return "";
  }

//--- คอลัมน์สุดท้ายที่มองเห็น (exclusive) เมื่อเริ่มดูจากคอลัมน์ 'first'
int VisibleLast(const int first)
  {
   int w = 0, c = first;
   while(c < N_COLS && w + ColW(c) <= VIEW_W)
     {
      w += ColW(c);
      c++;
     }
   return c;
  }

//--- ค่า first สูงสุดที่ยังเห็นคอลัมน์สุดท้าย
int MaxColScr()
  {
   for(int s = 0; s < N_COLS; s++)
      if(VisibleLast(s) >= N_COLS) return s;
   return 0;
  }

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

//--- เลื่อนแนวนอน (ใช้ร่วมกันทั้งสองกรอบ) delta > 0 = ไปทางขวา
void ScrollCols(const int deltaCols)
  {
   g_colScr += deltaCols;
   DrawDashboard();   // ถูกจำกัดช่วงใน DrawDashboard
  }

//--- คลิก = เลือกแถว, ดับเบิลคลิก = เปิด/ปิดแผง Detail (ไม่ส่งคำสั่งซื้อขาย)
void HandleClick(const int x, const int y)
  {
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
   if(dbl) g_detail = !g_detail;
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
         if((flags & 0x0004) != 0)   // กด Shift ค้าง -> เลื่อนแนวนอน
            ScrollCols((dparam < 0) ? HColStep : -HColStep);
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
      if(StringFind(sparam, PFX + "btn_") != 0) return;
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);

      if(sparam == PFX + "btn_us_up")      ScrollGroup(1, -WheelStep);
      else if(sparam == PFX + "btn_us_dn") ScrollGroup(1,  WheelStep);
      else if(sparam == PFX + "btn_ot_up") ScrollGroup(2, -WheelStep);
      else if(sparam == PFX + "btn_ot_dn") ScrollGroup(2,  WheelStep);
      else if(sparam == PFX + "btn_us_lf" || sparam == PFX + "btn_ot_lf") ScrollCols(-HColStep);
      else if(sparam == PFX + "btn_us_rt" || sparam == PFX + "btn_ot_rt") ScrollCols( HColStep);
     }
  }

//+------------------------------------------------------------------+
void BuildSymbolList()
  {
   int total = SymbolsTotal(UseMarketWatchOnly);
   ArrayResize(g_symbols, total);
   ArrayResize(g_lastBar, total);
   ArrayResize(g_lastBarFib, total);
   ArrayResize(g_cache, total);
   ArrayResize(g_fibCache, total);
   ArrayResize(g_isUs, total);

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
      g_lastBarFib[i] = 0;
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
void ResetFib(FibInfo &f)
  {
   f.ok   = false;
   f.dir  = 0;
   f.pA   = 0.0;
   f.pB   = 0.0;
   f.tA   = 0;
   f.tB   = 0;
   f.gzLo = 0.0;
   f.gzHi = 0.0;
  }

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
   ResetFib(r.fib);
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

void AddPend(PendC &a[], double hi, double lo, int dispBar, double sref)
  {
   int n = ArraySize(a);
   ArrayResize(a, n + 1);
   a[n].hi = hi;
   a[n].lo = lo;
   a[n].dispBar = dispBar;
   a[n].swingRef = sref;
  }

void AddOBI(OBI &a[], int dir, double hi, double lo, int bar)
  {
   int n = ArraySize(a);
   ArrayResize(a, n + 1);
   a[n].dir = dir;
   a[n].hi = hi;
   a[n].lo = lo;
   a[n].confirmBar = bar;
   a[n].mit = false;
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
//| Swing Quality Filter                                             |
//+------------------------------------------------------------------+
void AddSwing(SwingC &a[], double price, int bar)
  {
   int n = ArraySize(a);
   ArrayResize(a, n + 1);
   a[n].price   = price;
   a[n].bar     = bar;
   a[n].scanned = bar;
  }

void RemSwing(SwingC &a[], int k)
  {
   int n = ArraySize(a);
   for(int i = k; i < n - 1; i++)
      a[i] = a[i + 1];
   ArrayResize(a, n - 1);
  }

void QualifySwings(SwingC &sw[], const bool isHigh, const MqlRates &r[], const double &atr[],
                   const int i, double &structPrice, int &structBar, bool &hasStruct)
  {
   for(int s = ArraySize(sw) - 1; s >= 0; s--)
     {
      bool ok = false;
      for(int k = sw[s].scanned + 1; k <= i && !ok; k++)
        {
         bool strong = (atr[k] > 0.0) &&
                       (MathAbs(r[k].close - r[k].open) >= MinDispStrength * atr[k]);
         if(isHigh)
            ok = (strong && r[k].close < r[k].open) || (r[k].close > sw[s].price);
         else
            ok = (strong && r[k].close > r[k].open) || (r[k].close < sw[s].price);
        }
      sw[s].scanned = i;

      if(ok)
        {
         if(sw[s].bar > structBar)
           {
            structPrice = sw[s].price;
            structBar   = sw[s].bar;
            hasStruct   = true;
           }
         RemSwing(sw, s);
        }
      else if(i - sw[s].bar > SwingQualifyAge)
         RemSwing(sw, s);
     }
  }

//+------------------------------------------------------------------+
//| หา OB ล่าสุดที่เกิดขึ้น (ยืนยัน BOS ล่าสุด) ของ symbol เดียว        |
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
   int    structHighBar = -1, structLowBar = -1;
   double atrSum = 0, atrPrev = 0;

   double atrArr[];
   ArrayResize(atrArr, size);

   SwingC swH[], swL[];
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

      atrArr[i] = atrVal;

      //--- Swing structure + Swing Quality Filter
      double v;
      if(PivotHighAt(rates, i, v)) AddSwing(swH, v, i - SwingLength);
      if(PivotLowAt(rates, i, v))  AddSwing(swL, v, i - SwingLength);

      QualifySwings(swH, true,  rates, atrArr, i, structHigh, structHighBar, hasHigh);
      QualifySwings(swL, false, rates, atrArr, i, structLow,  structLowBar,  hasLow);

      //--- Displacement + ATR Quality Filter
      double body    = MathAbs(rates[i].close - rates[i].open);
      bool   passATR = (atrVal > 0.0) && (body >= MinDispStrength * atrVal);

      bool isBullDisp = passATR && rates[i].close > rates[i].open;
      bool isBearDisp = passATR && rates[i].close < rates[i].open;

      //--- STEP 1: Displacement + FVG -> Pending
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
            bool fvg = false;
            for(int j = 0; j <= MaxObToFvgDistance; j++)
              {
               int idx = i - j;
               if(idx - 2 < 0) break;
               if(rates[idx].low > rates[idx-2].high) fvg = true;
              }
            if(fvg)
               AddPend(pBull, rates[i-originIdx].high, rates[i-originIdx].low, i, structHigh);
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
            bool fvg = false;
            for(int j = 0; j <= MaxObToFvgDistance; j++)
              {
               int idx = i - j;
               if(idx - 2 < 0) break;
               if(rates[idx].high < rates[idx-2].low) fvg = true;
              }
            if(fvg)
               AddPend(pBear, rates[i-originIdx].high, rates[i-originIdx].low, i, structLow);
           }
        }

      //--- STEP 2: BOS confirmation
      for(int k = ArraySize(pBull) - 1; k >= 0; k--)
        {
         if(i - pBull[k].dispBar > MaxCandidateAge)
            RemPend(pBull, k);
         else if(rates[i].close < pBull[k].lo)
            RemPend(pBull, k);
         else if(rates[i].close > pBull[k].swingRef && i > pBull[k].dispBar)
           {
            AddOBI(obs, 1, pBull[k].hi, pBull[k].lo, i);
            RemPend(pBull, k);
           }
        }
      for(int k = ArraySize(pBear) - 1; k >= 0; k--)
        {
         if(i - pBear[k].dispBar > MaxCandidateAge)
            RemPend(pBear, k);
         else if(rates[i].close > pBear[k].hi)
            RemPend(pBear, k);
         else if(rates[i].close < pBear[k].swingRef && i > pBear[k].dispBar)
           {
            AddOBI(obs, -1, pBear[k].hi, pBear[k].lo, i);
            RemPend(pBear, k);
           }
        }

      //--- STEP 3: Mitigation
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
         if(isMit) obs[m].mit = true;
        }
     }

   int n = ArraySize(obs);
   if(n == 0) return(true);

   int L = n - 1;
   res.hasOB       = true;
   res.dir         = obs[L].dir;
   res.obHigh      = obs[L].hi;
   res.obLow       = obs[L].lo;
   res.retested    = obs[L].mit;
   res.confirmTime = rates[obs[L].confirmBar].time;
   res.barsAgo     = (size - 1) - obs[L].confirmBar;
   return(true);
  }

//+------------------------------------------------------------------+
//| Auto Fibonacci: หา Impulse จาก Qualified Swing High/Low (M5)      |
//|  - ใช้ Swing ที่ผ่าน QualifySwings เดิมเท่านั้น                    |
//|  - Bullish: Qualified Low -> Qualified High (High เป็นจุดล่าสุด)   |
//|  - Bearish: Qualified High -> Qualified Low (Low เป็นจุดล่าสุด)    |
//|  - ถ้าหาไม่ได้ / ขาสั้นเกินไป / Impulse ถูกทำลาย -> fi.ok = false  |
//| คืนค่า false เฉพาะกรณีข้อมูลไม่พอ (เพื่อไม่ให้ cache)              |
//+------------------------------------------------------------------+
bool ScanSymbolFib(const string sym, FibInfo &fi)
  {
   ResetFib(fi);

   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   int size = CopyRates(sym, FibTimeframe, 1, FibLookbackBars, rates);
   if(size < SwingLength * 2 + AtrLength + 5) return(false);

   double structHigh = 0, structLow = 0;
   bool   hasHigh = false, hasLow = false;
   int    structHighBar = -1, structLowBar = -1;
   double atrSum = 0, atrPrev = 0;

   double atrArr[];
   ArrayResize(atrArr, size);

   SwingC swH[], swL[];     // Swing ที่รอการตรวจคุณภาพ
   SwingC qH[], qL[];       // Qualified Swing (เรียงตามแท่ง เก่า -> ใหม่)

   for(int i = 0; i < size; i++)
     {
      //--- ATR (RMA) เหมือนเดิม
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
      atrArr[i] = atrVal;

      //--- Swing + Swing Quality Filter (ฟังก์ชันเดิม)
      double v;
      if(PivotHighAt(rates, i, v)) AddSwing(swH, v, i - SwingLength);
      if(PivotLowAt(rates, i, v))  AddSwing(swL, v, i - SwingLength);

      int prevHB = structHighBar;
      int prevLB = structLowBar;
      QualifySwings(swH, true,  rates, atrArr, i, structHigh, structHighBar, hasHigh);
      QualifySwings(swL, false, rates, atrArr, i, structLow,  structLowBar,  hasLow);

      //--- เก็บเฉพาะ Swing ที่เพิ่งผ่านเกณฑ์
      if(structHighBar != prevHB) AddSwing(qH, structHigh, structHighBar);
      if(structLowBar  != prevLB) AddSwing(qL, structLow,  structLowBar);
     }

   int nH = ArraySize(qH);
   int nL = ArraySize(qL);
   if(nH < 1 || nL < 1) return(true);                 // ยังไม่มีคู่ Qualified Swing -> N/A

   int lastH = qH[nH-1].bar;
   int lastL = qL[nL-1].bar;
   if(lastH == lastL) return(true);

   bool   bull = (lastH > lastL);                     // จุดล่าสุดเป็น High = Bullish impulse
   int    endBar, startBar;
   double endP, startP;

   if(bull)
     {
      endBar = lastH;
      endP   = qH[nH-1].price;
      int prevBound = (nH >= 2) ? qH[nH-2].bar : -1;  // เอา Low ที่ต่ำสุดในช่วงระหว่าง High ก่อนหน้า -> High ล่าสุด
      int best = -1;
      for(int k = nL - 1; k >= 0; k--)
        {
         if(qL[k].bar >= endBar) continue;
         if(qL[k].bar <= prevBound) break;
         if(best < 0 || qL[k].price < qL[best].price) best = k;
        }
      if(best < 0) best = nL - 1;                     // fallback: Qualified Low ล่าสุด
      startBar = qL[best].bar;
      startP   = qL[best].price;
      if(!(endP > startP)) return(true);
     }
   else
     {
      endBar = lastL;
      endP   = qL[nL-1].price;
      int prevBound = (nL >= 2) ? qL[nL-2].bar : -1;  // เอา High ที่สูงสุดในช่วงระหว่าง Low ก่อนหน้า -> Low ล่าสุด
      int best = -1;
      for(int k = nH - 1; k >= 0; k--)
        {
         if(qH[k].bar >= endBar) continue;
         if(qH[k].bar <= prevBound) break;
         if(best < 0 || qH[k].price > qH[best].price) best = k;
        }
      if(best < 0) best = nH - 1;
      startBar = qH[best].bar;
      startP   = qH[best].price;
      if(!(startP > endP)) return(true);
     }

   //--- ขา Impulse ต้องใหญ่พอ (ไม่ใช้ Pivot เล็กๆ)
   double range = MathAbs(endP - startP);
   double atrNow = atrArr[size - 1];
   if(atrNow <= 0.0 || range < FibMinLegATR * atrNow) return(true);

   //--- Impulse ถูกทำลาย (ราคาปิดทะลุจุดเริ่ม) -> ไม่ใช้
   for(int j = endBar + 1; j < size; j++)
     {
      if(bull  && rates[j].close < startP) return(true);
      if(!bull && rates[j].close > startP) return(true);
     }

   //--- Golden Zone (0.618 - 0.786 retracement จากจุดจบ Impulse)
   double p1, p2;
   if(bull)
     {
      p1 = endP - FibGoldenUpper * range;
      p2 = endP - FibGoldenLower * range;
     }
   else
     {
      p1 = endP + FibGoldenUpper * range;
      p2 = endP + FibGoldenLower * range;
     }

   fi.ok   = true;
   fi.dir  = bull ? 1 : -1;
   fi.pA   = startP;
   fi.pB   = endP;
   fi.tA   = rates[startBar].time;
   fi.tB   = rates[endBar].time;
   fi.gzLo = MathMin(p1, p2);
   fi.gzHi = MathMax(p1, p2);
   return(true);
  }

//+------------------------------------------------------------------+
//| วาด / อัปเดต OBJ_FIBO บนกราฟปัจจุบัน                              |
//+------------------------------------------------------------------+
void UpdateFiboObject(const FibInfo &fi)
  {
   string name = PFX + "fibo";

   if(!DrawFibOnChart || !fi.ok)
     {
      if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
      g_fibTA = 0; g_fibTB = 0; g_fibPA = 0; g_fibPB = 0;
      return;
     }

   // ไม่เปลี่ยน Qualified Swing ชุดเดิม -> ไม่ต้องวาดใหม่
   if(ObjectFind(0, name) >= 0 &&
      g_fibTA == fi.tA && g_fibTB == fi.tB && g_fibPA == fi.pA && g_fibPB == fi.pB)
      return;

   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);

   // MT5: Level 0 อยู่ที่จุดที่ 2 (จุดจบ Impulse), Level 1 อยู่ที่จุดที่ 1 (จุดเริ่ม)
   if(!ObjectCreate(0, name, OBJ_FIBO, 0, fi.tA, fi.pA, fi.tB, fi.pB))
      return;

   double lv[7] = {0.0, 0.236, 0.382, 0.5, 0.0, 0.0, 1.0};
   lv[4] = FibGoldenUpper;
   lv[5] = FibGoldenLower;

   ObjectSetInteger(0, name, OBJPROP_COLOR, FibColor);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_LEVELS, 7);

   for(int i = 0; i < 7; i++)
     {
      bool golden = (lv[i] == FibGoldenUpper || lv[i] == FibGoldenLower);
      ObjectSetDouble(0, name, OBJPROP_LEVELVALUE, i, lv[i]);
      ObjectSetInteger(0, name, OBJPROP_LEVELCOLOR, i, golden ? FibGoldenColor : FibColor);
      ObjectSetInteger(0, name, OBJPROP_LEVELSTYLE, i, golden ? STYLE_SOLID : STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_LEVELWIDTH, i, golden ? 2 : 1);
      ObjectSetString(0, name, OBJPROP_LEVELTEXT, i, DoubleToString(lv[i], 3) + " (%$)");
     }

   g_fibTA = fi.tA; g_fibTB = fi.tB; g_fibPA = fi.pA; g_fibPB = fi.pB;
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

   bool    chartFibDone = false;
   FibInfo chartFib;
   ResetFib(chartFib);

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

      //--- Fibonacci / Golden Zone (M5) - cache แยกต่างหาก
      FibInfo fi;
      ResetFib(fi);
      datetime bf = iTime(g_symbols[i], FibTimeframe, 0);
      if(bf != 0 && bf == g_lastBarFib[i])
         fi = g_fibCache[i];
      else if(ScanSymbolFib(g_symbols[i], fi))
        {
         g_fibCache[i]   = fi;
         g_lastBarFib[i] = bf;
        }
      r.fib = fi;

      if(g_symbols[i] == _Symbol)
        {
         chartFib = fi;
         chartFibDone = true;
        }

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

   //--- Symbol ของกราฟไม่อยู่ในรายการ -> สแกนแยก
   if(!chartFibDone)
      ScanSymbolFib(_Symbol, chartFib);
   UpdateFiboObject(chartFib);

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

//--- วางข้อความในเซลล์ของคอลัมน์ (x = ขอบซ้ายของเซลล์)
void PlaceCell(const string name, const string text, const int x, const int w, const bool right,
               const int y, const color clr, const int size, const bool bold)
  {
   if(right) SetLbl(name, text, x + w - 10, y, clr, size, bold, ANCHOR_RIGHT_UPPER);
   else      SetLbl(name, text, x,          y, clr, size, bold, ANCHOR_LEFT_UPPER);
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
      case 2:   // LATEST OB
         if(r.hasOB)
           {
            txt = (r.dir == 1) ? "BULL OB" : "BEAR OB";
            clr = (r.dir == 1) ? C_GREEN : C_RED;
           }
         return;
      case 3:   // OB ZONE
         if(r.hasOB)
           {
            txt = Fmt(r.obHigh, r.digits) + " / " + Fmt(r.obLow, r.digits);
            clr = C_HDR;
           }
         return;
      case 4:   // STATUS
         if(r.hasOB)
           {
            txt = r.retested ? "Retested" : "NOT Retested";
            clr = r.retested ? C_MUTED : C_YELLOW;
           }
         return;
      case 5:   // GOLDEN ZONE
         if(r.fib.ok)
           {
            txt = Fmt(r.fib.gzLo, r.digits) + " - " + Fmt(r.fib.gzHi, r.digits);
            clr = C_GOLD;
           }
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

   // คอลัมน์ที่เลื่อนได้
   int x = DashX + SYM_W;
   for(int c = g_colFirst; c < g_colLast; c++)
     {
      string txt;
      color  clr;
      CellOf(r, c, txt, clr);
      PlaceCell("row_c" + IntegerToString(c) + "_" + id, txt, x, ColW(c), ColRight(c), y, clr, F, false);
      x += ColW(c);
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

   string rng = (count == 0) ? "0" :
                IntegerToString(scr + 1) + "-" + IntegerToString(MathMin(scr + view, count)) +
                " / " + IntegerToString(count);
   SetLbl("hdr_" + tag + "_title", title + "  [" + rng + "]", DashX, y0 + 5, FrameColor, 10, true);

   // ปุ่มเลื่อนแนวตั้ง (แสดงเฉพาะเมื่อมีแถวเกินกรอบ)
   if(count > view)
     {
      SetButton(PFX + "btn_" + tag + "_up", "▲", DashX + PANEL_W - 62, y0 + 4);
      SetButton(PFX + "btn_" + tag + "_dn", "▼", DashX + PANEL_W - 36, y0 + 4);
     }
   else
     {
      ObjectDelete(0, PFX + "btn_" + tag + "_up");
      ObjectDelete(0, PFX + "btn_" + tag + "_dn");
     }

   // ปุ่มเลื่อนแนวนอน (แสดงเฉพาะเมื่อคอลัมน์เกินความกว้าง)
   if(g_colMax > 0)
     {
      SetButton(PFX + "btn_" + tag + "_lf", "◄", DashX + PANEL_W - 114, y0 + 4);
      SetButton(PFX + "btn_" + tag + "_rt", "►", DashX + PANEL_W - 88,  y0 + 4);
     }
   else
     {
      ObjectDelete(0, PFX + "btn_" + tag + "_lf");
      ObjectDelete(0, PFX + "btn_" + tag + "_rt");
     }

   // แถวหัวตาราง: SYMBOL (ตรึง) + คอลัมน์ที่มองเห็น
   int hy = y0 + 24;
   SetLbl("hdr_" + tag + "_sym", "SYMBOL", DashX, hy, C_HDR, F, true);
   int hx = DashX + SYM_W;
   for(int c = g_colFirst; c < g_colLast; c++)
     {
      PlaceCell("hdr_" + tag + "_c" + IntegerToString(c), ColHdr(c), hx, ColW(c), ColRight(c), hy, C_HDR, F, true);
      hx += ColW(c);
     }
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

//--- แผง Detail (ดับเบิลคลิกที่แถว) - แสดงข้อมูลวิเคราะห์เท่านั้น ไม่มีคำสั่งซื้อขาย
int DrawDetail(const int y0)
  {
   const int F = 9;
   ScanResult w;
   SetRect("sep_det", DashX - 8, y0, PANEL_W, 1, FrameColor, FrameColor);

   if(!FindRow(g_sel, w))
     {
      SetLbl("det_0", "No symbol selected", DashX, y0 + 6, C_MUTED, F, false);
      return y0 + 26;
     }

   int d = w.digits;
   string head = "DETAIL  " + w.symbol;
   if(w.hasOB)
      head += "   " + string(w.dir == 1 ? "BULL OB" : "BEAR OB") + "   " + (w.retested ? "Retested" : "NOT Retested");
   SetLbl("det_0", head, DashX, y0 + 6, FrameColor, 10, true);

   if(w.pctValid)
      SetLbl("det_1", "Price " + Fmt(w.price, d) + "   Ref(" + OpenRefText() + ") " + Fmt(w.openPrice, d) +
             "   Chg " + (w.pct >= 0 ? "+" : "") + DoubleToString(w.pct, 2) + "%",
             DashX, y0 + 26, C_HDR, F, false);
   else
      SetLbl("det_1", "Price: n/a", DashX, y0 + 26, C_MUTED, F, false);

   if(w.hasOB)
      SetLbl("det_2", "Latest OB " + TfText(g_tf) + "   Zone " + Fmt(w.obHigh, d) + " / " + Fmt(w.obLow, d) +
             "   Confirmed " + TimeToString(w.confirmTime, TIME_DATE | TIME_MINUTES) +
             " (" + IntegerToString(w.barsAgo) + " bars ago)",
             DashX, y0 + 42, C_HDR, F, false);
   else
      SetLbl("det_2", "Latest OB: none found", DashX, y0 + 42, C_MUTED, F, false);

   if(w.fib.ok)
      SetLbl("det_3", "Fibo " + TfText(FibTimeframe) + "   " + string(w.fib.dir == 1 ? "BULL" : "BEAR") +
             " impulse " + Fmt(w.fib.pA, d) + " -> " + Fmt(w.fib.pB, d) +
             "   Golden Zone " + Fmt(w.fib.gzLo, d) + " - " + Fmt(w.fib.gzHi, d),
             DashX, y0 + 58, C_GOLD, F, false);
   else
      SetLbl("det_3", "Fibo " + TfText(FibTimeframe) + ": n/a (no valid impulse)", DashX, y0 + 58, C_MUTED, F, false);

   SetLbl("det_4", "Analysis only. This EA never sends orders.", DashX, y0 + 78, C_MUTED, 8, false);
   return y0 + 98;
  }

void DrawDashboard()
  {
   ObjectsDeleteAll(0, PFX + "row_");
   ObjectsDeleteAll(0, PFX + "hdr_");
   ObjectsDeleteAll(0, PFX + "det_");
   ObjectDelete(0, PFX + "sep_det");

   // สร้างกรอบนอกก่อน เพื่อให้อยู่ใต้ object อื่นทั้งหมด (ปรับขนาดตอนท้าย)
   if(ObjectFind(0, PFX + "frame") < 0)
      SetRect("frame", DashX - 8, DashY - 8, PANEL_W, 10, C_BG, FrameColor);

   g_viewUS = MathMax(1, ViewRowsUS);
   g_viewOT = MathMax(1, ViewRowsOther);

   // ช่วงเลื่อนแนวนอน + คอลัมน์ที่มองเห็น
   g_colMax = MaxColScr();
   if(g_colScr > g_colMax) g_colScr = g_colMax;
   if(g_colScr < 0)        g_colScr = 0;
   g_colFirst = g_colScr;
   g_colLast  = VisibleLast(g_colFirst);

   // ส่วนหัว
   SetLbl("hdr_title",    "MARKET SCANNER", DashX, DashY, C_HDR, 12, true);
   SetLbl("hdr_subtitle", "Order Block " + TfText(g_tf) + " | Golden Zone " + TfText(FibTimeframe),
          DashX, DashY + 20, C_MUTED, 9, false);
   string colTxt = (g_colMax > 0)
                   ? " | cols " + IntegerToString(g_colFirst + 1) + "-" + IntegerToString(g_colLast) +
                     "/" + IntegerToString(N_COLS) + " (Shift+wheel)"
                   : "";
   SetLbl("hdr_stats", "% vs " + OpenRefText() + " | " + IntegerToString(g_found) + " sym, " +
          IntegerToString(g_withOB) + " OB" + colTxt,
          DashX + PANEL_W - 16, DashY + 4, C_MUTED, 8, false, ANCHOR_RIGHT_UPPER);

   g_usTop  = DashY + 38;
   g_usBot  = g_usTop + SectionHeight(g_viewUS);
   g_usRow0 = g_usTop + 42;
   g_otTop  = g_usBot;
   g_otBot  = g_otTop + SectionHeight(g_viewOT);
   g_otRow0 = g_otTop + 42;

   int bottom = DrawSection("us", "US STOCKS", g_us, ArraySize(g_us), g_scrUs, g_viewUS, g_usTop);
   bottom     = DrawSection("ot", "OTHER",     g_ot, ArraySize(g_ot), g_scrOt, g_viewOT, g_otTop);
   if(g_detail)
      bottom = DrawDetail(bottom);

   // กรอบนอก
   SetRect("frame", DashX - 8, DashY - 8, PANEL_W, bottom - (DashY - 8) + 2, C_BG, FrameColor);

   ChartRedraw();
  }
//+------------------------------------------------------------------+