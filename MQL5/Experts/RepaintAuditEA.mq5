//+------------------------------------------------------------------+
//| RepaintAuditEA.mq5 - logger for Strategy Tester (no trading)     |
//+------------------------------------------------------------------+
#property strict

input string InpIndicatorName = "SwingStructure";   // indicator file name under MQL5/Indicators (no extension)
input int    InpStrength      = 3;                  // passed to the indicator
input int    InpBuffers       = 5;                  // log buffers 0..InpBuffers-1
input int    InpLookback      = 6;                  // on each new bar, re-read bars shift 1..InpLookback
input string InpTag           = "";                 // appended to output file names (optional)

int      handle        = INVALID_HANDLE;
int      liveHandle    = INVALID_HANDLE;
datetime firstBarTime  = 0;
datetime lastBarTime   = 0;
string   liveName      = "";
string   finalName     = "";

//+------------------------------------------------------------------+
//| Format one indicator value at buffer buf, shift shift            |
//+------------------------------------------------------------------+
string ValueText(const int buf, const int shift)
{
   double v[];
   if(CopyBuffer(handle, buf, shift, 1, v) != 1)
      return "NA";
   if(v[0] >= DBL_MAX/2)
      return "EMPTY";
   return DoubleToString(v[0], _Digits);
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   liveName  = "repaint_live_"  + InpIndicatorName + InpTag + ".csv";
   finalName = "repaint_final_" + InpIndicatorName + InpTag + ".csv";

   handle = iCustom(_Symbol, _Period, InpIndicatorName, InpStrength);
   if(handle == INVALID_HANDLE)
      return INIT_FAILED;

   firstBarTime = iTime(_Symbol, _Period, 0);

   liveHandle = FileOpen(liveName, FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON, ',');
   if(liveHandle == INVALID_HANDLE)
   {
      IndicatorRelease(handle);
      handle = INVALID_HANDLE;
      return INIT_FAILED;
   }
   FileWrite(liveHandle, "observed_at", "bar_time", "buffer", "value");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime t0 = iTime(_Symbol, _Period, 0);
   if(t0 == lastBarTime)
      return;

   bool firstCall = (lastBarTime == 0);
   lastBarTime = t0;
   if(firstCall)
      return;
   if(liveHandle == INVALID_HANDLE)
      return;

   datetime observedAt = iTime(_Symbol, _Period, 1);
   string observed = TimeToString(observedAt, TIME_DATE|TIME_MINUTES);

   for(int k = 1; k <= InpLookback; k++)
   {
      datetime bt = iTime(_Symbol, _Period, k);
      if(bt < firstBarTime)
         continue;
      string barText = TimeToString(bt, TIME_DATE|TIME_MINUTES);
      for(int b = 0; b < InpBuffers; b++)
         FileWrite(liveHandle, observed, barText, b, ValueText(b, k));
   }
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   int fh = FileOpen(finalName, FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON, ',');
   if(fh != INVALID_HANDLE)
   {
      FileWrite(fh, "bar_time", "buffer", "value");
      int n = Bars(_Symbol, _Period);
      for(int k = 1; k < n; k++)
      {
         datetime bt = iTime(_Symbol, _Period, k);
         if(bt < firstBarTime)
            continue;
         string barText = TimeToString(bt, TIME_DATE|TIME_MINUTES);
         for(int b = 0; b < InpBuffers; b++)
            FileWrite(fh, barText, b, ValueText(b, k));
      }
      FileClose(fh);
   }

   if(liveHandle != INVALID_HANDLE)
   {
      FileClose(liveHandle);
      liveHandle = INVALID_HANDLE;
   }

   if(handle != INVALID_HANDLE)
   {
      IndicatorRelease(handle);
      handle = INVALID_HANDLE;
   }

   string common = TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files\\";
   Print("RepaintAuditEA live CSV: ",  common + liveName);
   Print("RepaintAuditEA final CSV: ", common + finalName);
}
//+------------------------------------------------------------------+
