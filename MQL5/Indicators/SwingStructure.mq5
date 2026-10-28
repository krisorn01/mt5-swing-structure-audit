//+------------------------------------------------------------------+
//| SwingStructure.mq5                                               |
//| Honest, non-repainting swing / structure indicator (WO-1).       |
//|                                                                  |
//| Non-repaint rules:                                               |
//| 1. Writes only to closed bars (index <= rates_total-2). The      |
//|    forming bar (rates_total-1) is only ever set to "nothing".   |
//| 2. A value, once written, is never rewritten (pivot arrows are   |
//|    written once at confirmation; signals and state once at bar   |
//|    close).                                                       |
//| 3. Pivot confirmation uses only bars <= i; break detection uses  |
//|    only close[i] and pivots confirmed at or before i.            |
//| 4. Incremental start = prev_calculated-1 so every closed bar is  |
//|    processed exactly once; full recompute only when              |
//|    prev_calculated==0 (history reload), which resets the state.  |
//|                                                                  |
//| Edge: if a high-break and a low-break happen on the same bar,    |
//| the high break is evaluated first (as written).                  |
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

   IndicatorSetString(INDICATOR_SHORTNAME, "SwingStructure");
   ResetState();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Calculation: processes each closed bar exactly once.             |
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
      start = prev_calculated - 1;   // the bar that just closed

   for(int i = start; i <= rates_total - 2; i++)
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

      // (b) breaks, evaluated on close[i] of the closed bar i
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
   }

   // forming bar: explicitly set to "nothing" each call
   const int f = rates_total - 1;
   SwingHighBuf[f] = EMPTY_VALUE;
   SwingLowBuf[f]  = EMPTY_VALUE;
   BuyArrowBuf[f]  = EMPTY_VALUE;
   SellArrowBuf[f] = EMPTY_VALUE;
   StructureBuf[f] = 0.0;
   LastHighBuf[f]  = EMPTY_VALUE;
   LastLowBuf[f]   = EMPTY_VALUE;

   return rates_total;
}
