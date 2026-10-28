//+------------------------------------------------------------------+
//| SwingStructure_RepaintDemo.mq5                                   |
//| NEGATIVE CONTROL for the audit harness - do not trade with it.   |
//| Deliberately repainting variant of SwingStructure.mq5 (WO-2).    |
//+------------------------------------------------------------------+
#property copyright "Krisorn Intakorn"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots   6

input int InpStrength = 3;   // bars required on each side of a pivot (>=1)

double SwingHighBuf[];
double SwingLowBuf[];
double BuyArrowBuf[];
double SellArrowBuf[];
double StructureBuf[];
double LastHighBuf[];
double LastLowBuf[];

int    lastHighBar   = -1;
double lastHighPrice = 0.0;
bool   highBroken    = false;
int    lastLowBar    = -1;
double lastLowPrice  = 0.0;
bool   lowBroken     = false;
int    structure     = 0;

// state snapshots per bar (used by DEFECT 2 rewind)
int    stHighBar[];
double stHighPrice[];
bool   stHighBroken[];
int    stLowBar[];
double stLowPrice[];
bool   stLowBroken[];
int    stStructure[];

//+------------------------------------------------------------------+
//| Swing high at p: strict high comparison on both sides, k=1..S.   |
//+------------------------------------------------------------------+
bool IsSwingHigh(const int p,const int S,const double &high[])
{
   for(int k=1; k<=S; k++)
   {
      if(!(high[p] > high[p-k])) return false;
      if(!(high[p] > high[p+k])) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Swing low at p: strict low comparison on both sides, k=1..S.     |
//+------------------------------------------------------------------+
bool IsSwingLow(const int p,const int S,const double &low[])
{
   for(int k=1; k<=S; k++)
   {
      if(!(low[p] < low[p-k])) return false;
      if(!(low[p] < low[p+k])) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Reset all persistent state to "none".                            |
//+------------------------------------------------------------------+
void ResetState()
{
   lastHighBar   = -1;
   lastHighPrice = 0.0;
   highBroken    = false;
   lastLowBar    = -1;
   lastLowPrice  = 0.0;
   lowBroken     = false;
   structure     = 0;
}

//+------------------------------------------------------------------+
//| Save current state into the per-bar snapshot at idx.             |
//+------------------------------------------------------------------+
void SaveSnapshot(const int idx)
{
   stHighBar[idx]    = lastHighBar;
   stHighPrice[idx]  = lastHighPrice;
   stHighBroken[idx] = highBroken;
   stLowBar[idx]     = lastLowBar;
   stLowPrice[idx]   = lastLowPrice;
   stLowBroken[idx]  = lowBroken;
   stStructure[idx]  = structure;
}

//+------------------------------------------------------------------+
//| Restore state from the per-bar snapshot at idx.                  |
//+------------------------------------------------------------------+
void LoadSnapshot(const int idx)
{
   lastHighBar   = stHighBar[idx];
   lastHighPrice = stHighPrice[idx];
   highBroken    = stHighBroken[idx];
   lastLowBar    = stLowBar[idx];
   lastLowPrice  = stLowPrice[idx];
   lowBroken     = stLowBroken[idx];
   structure     = stStructure[idx];
}

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpStrength < 1)
   {
      Print("SwingStructure: InpStrength must be >= 1");
      return INIT_PARAMETERS_INCORRECT;
   }

   SetIndexBuffer(0, SwingHighBuf,  INDICATOR_DATA);
   SetIndexBuffer(1, SwingLowBuf,   INDICATOR_DATA);
   SetIndexBuffer(2, BuyArrowBuf,   INDICATOR_DATA);
   SetIndexBuffer(3, SellArrowBuf,  INDICATOR_DATA);
   SetIndexBuffer(4, StructureBuf,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(5, LastHighBuf,   INDICATOR_DATA);
   SetIndexBuffer(6, LastLowBuf,    INDICATOR_DATA);

   ArraySetAsSeries(SwingHighBuf, false);
   ArraySetAsSeries(SwingLowBuf,  false);
   ArraySetAsSeries(BuyArrowBuf,  false);
   ArraySetAsSeries(SellArrowBuf, false);
   ArraySetAsSeries(StructureBuf, false);
   ArraySetAsSeries(LastHighBuf,  false);
   ArraySetAsSeries(LastLowBuf,   false);

   // plot 0: swing high dot
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_ARROW);
   PlotIndexSetInteger(0, PLOT_ARROW, 159);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, clrRed);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetString(0, PLOT_LABEL, "SwingHigh");

   // plot 1: swing low dot
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_ARROW);
   PlotIndexSetInteger(1, PLOT_ARROW, 159);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, clrDodgerBlue);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetString(1, PLOT_LABEL, "SwingLow");

   // plot 2: buy (reversal up) arrow
   PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_ARROW);
   PlotIndexSetInteger(2, PLOT_ARROW, 233);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, clrLime);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetString(2, PLOT_LABEL, "BuySignal");

   // plot 3: sell (reversal down) arrow
   PlotIndexSetInteger(3, PLOT_DRAW_TYPE, DRAW_ARROW);
   PlotIndexSetInteger(3, PLOT_ARROW, 234);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, clrOrangeRed);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetString(3, PLOT_LABEL, "SellSignal");

   // plot 4: last confirmed swing high line
   PlotIndexSetInteger(4, PLOT_DRAW_TYPE, DRAW_LINE);
   PlotIndexSetInteger(4, PLOT_LINE_STYLE, STYLE_DOT);
   PlotIndexSetInteger(4, PLOT_LINE_WIDTH, 1);
   PlotIndexSetInteger(4, PLOT_LINE_COLOR, clrRed);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetString(4, PLOT_LABEL, "LastHigh");

   // plot 5: last confirmed swing low line
   PlotIndexSetInteger(5, PLOT_DRAW_TYPE, DRAW_LINE);
   PlotIndexSetInteger(5, PLOT_LINE_STYLE, STYLE_DOT);
   PlotIndexSetInteger(5, PLOT_LINE_WIDTH, 1);
   PlotIndexSetInteger(5, PLOT_LINE_COLOR, clrDodgerBlue);
   PlotIndexSetDouble(5, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetString(5, PLOT_LABEL, "LastLow");

   IndicatorSetString(INDICATOR_SHORTNAME, "SwingStructure_RepaintDemo");
   ResetState();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Calculation (repainting demo).                                   |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < 1) return 0;

   const int S = InpStrength;
   int start;

   if(ArraySize(stHighBar) < rates_total)
   {
      ArrayResize(stHighBar,    rates_total);
      ArrayResize(stHighPrice,  rates_total);
      ArrayResize(stHighBroken, rates_total);
      ArrayResize(stLowBar,     rates_total);
      ArrayResize(stLowPrice,   rates_total);
      ArrayResize(stLowBroken,  rates_total);
      ArrayResize(stStructure,  rates_total);
   }

   if(prev_calculated == 0)
   {
      ResetState();
      ArrayInitialize(SwingHighBuf, EMPTY_VALUE);
      ArrayInitialize(SwingLowBuf,  EMPTY_VALUE);
      ArrayInitialize(BuyArrowBuf,  EMPTY_VALUE);
      ArrayInitialize(SellArrowBuf, EMPTY_VALUE);
      ArrayInitialize(StructureBuf, 0.0);
      ArrayInitialize(LastHighBuf,  EMPTY_VALUE);
      ArrayInitialize(LastLowBuf,   EMPTY_VALUE);
      start = 2*S;
   }
   else
   {
      // DEFECT 2: recompute the last S+2 bars on every call
      start = MathMax(2*S, prev_calculated - S - 2);
      for(int j = start; j <= rates_total - 1; j++)
      {
         SwingHighBuf[j] = EMPTY_VALUE;
         SwingLowBuf[j]  = EMPTY_VALUE;
         BuyArrowBuf[j]  = EMPTY_VALUE;
         SellArrowBuf[j] = EMPTY_VALUE;
      }
      LoadSnapshot(start - 1);   // rewind state to bar start-1
   }

   // DEFECT 1: loop bound reaches the forming bar (rates_total-1); pivot right side p+S may use it
   for(int i = start; i <= rates_total - 1; i++)
   {
      // (a) confirm pivots whose S-th right bar is i
      int p = i - S;
      if(p - S >= 0)
      {
         if(IsSwingHigh(p, S, high))
         {
            SwingHighBuf[p] = high[p] + 2*_Point;
            lastHighPrice = high[p];
            lastHighBar   = p;
            highBroken    = false;
         }
         if(IsSwingLow(p, S, low))
         {
            SwingLowBuf[p] = low[p] - 2*_Point;
            lastLowPrice   = low[p];
            lastLowBar     = p;
            lowBroken      = false;
         }
      }

      // (b) breaks, evaluated on close[i]
      // DEFECT 3: close[i] is used even when i is the forming bar (rates_total-1), so the signal can vanish
      if(lastHighBar >= 0 && !highBroken && close[i] > lastHighPrice)
      {
         highBroken = true;
         if(structure != 1)
         {
            BuyArrowBuf[i] = low[i] - 5*_Point;
            structure = 1;
         }
      }
      if(lastLowBar >= 0 && !lowBroken && close[i] < lastLowPrice)
      {
         lowBroken = true;
         if(structure != -1)
         {
            SellArrowBuf[i] = high[i] + 5*_Point;
            structure = -1;
         }
      }

      // (c) per-bar state outputs
      StructureBuf[i] = structure;
      LastHighBuf[i]  = (lastHighBar >= 0 ? lastHighPrice : EMPTY_VALUE);
      LastLowBuf[i]   = (lastLowBar  >= 0 ? lastLowPrice  : EMPTY_VALUE);
      SaveSnapshot(i);
   }

   return rates_total;
}
