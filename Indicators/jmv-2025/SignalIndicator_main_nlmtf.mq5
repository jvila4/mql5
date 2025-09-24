//+------------------------------------------------------------------+
//|                                   SignalIndicator_main_nlmtf.mq5 |
//|                                 NonLag MA MTF with Interpolation |
//+------------------------------------------------------------------+
// Description:                                                      |
//    Indicador de señales basado en el color del indicador custom   |
// "NonLag MA mtf". Este indicador dibuja flechas de compra cuando   |
// el buffer de colores de "NonLag MA mtf" cambia a 2 (color verde)  |
// y flechas de venta cuando cambia a 1 (color rosa). Se puede       |
// ajustar el marco de tiempo y parámetros del NonLag MA a través de |
// inputs. En futuras versiones se pueden añadir filtros adicionales.|
//+------------------------------------------------------------------+
#include <jmv-2025/SignalRules.mqh>

#property copyright "Copyright 2025, JmVila"
#property link      "https://www.mql5.com"
#property version   "1.00"

#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   3

// Plot 1: NonLag MTFi línea coloreada
#property indicator_label1  "NonLag MA Line"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrDarkGray,clrDeepPink,clrLimeGreen
#property indicator_width1  2

// Plot 2: flechas SELL
#property indicator_label2  "Sell_NL_Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrDeepPink
#property indicator_width2  2

// Plot 3: flechas BUY
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrLimeGreen
#property indicator_width3  2

// =================== Parámetros NonLag base ===================
input ENUM_TIMEFRAMES NL_TimeFrame = PERIOD_CURRENT;  // Time frame del NonLag MA
input double          NL_Period    = 7;               // Periodo del NonLag MA, default 27, tested also 12
input ENUM_APPLIED_PRICE NL_Price  = PRICE_WEIGHTED;  // Precio aplicado
input bool            NL_Interpolate = true;          // Interpolación en modo MTF

input int    CanalPeriod               = 40;       // Periodo para canal sobre NonLagBuffer
input double CanalWidthMultiplier      = 1.5;      // Multiplicador de la desviación estándar
input double CanalMarginRatio          = 0.1;      // Ratio del canal desde el borde donde evitar señales

input int Arrows_Offset                = 5;        // Offset de flechas

// Estocástico opcional
input bool UseStochasticFilter = false;  // Activar filtro estocástico
input int KPeriod = 5;
input int DPeriod = 3;
input int Slowing = 3;

// =================== Reglas LRAC / NLMA ===================
input bool  LRAC_FilterON                       = true;    // LRAC - Activar filtro
input bool  LRAC_Rule1_MinWidth                 = true;     // LRAC Regla 1: ancho mínimo del canal
input bool  LRAC_Rule2_CorrectBand              = true;     // LRAC Regla 2: mitad correcta del canal
input bool  LRAC_Rule2_UseTolerance             = true;     // Permitir margen cerca de la media
input double LRAC_Rule2_TolerancePct            = 0.15;     // 15% del ancho del canal como tolerancia
input bool  LRAC_RequireTrendSide               = false;
input bool  LRAC_Rule3a_HTF_BandMatchesSignal   = true;    // LRAC Regla 3a: mitad HTF compatible con la señal
input bool  LRAC_Rule3b_HTF_SlopeMatchesSignal  = false;    // LRAC Regla 3b: pend. HTF compatible con la señal (±1)
input bool  LRAC_Rule3c_HTF_SlopeEqualsCTF      = false;    // LRAC Regla 3c: pend. HTF igual a CTF (incluye FLAT)
input bool  LRAC_Rule4_HTF_Dominant             = false;    // LRAC Regla 4: HTF dominante (solo compra si HTF alcista, etc.)

// NLMA HTF (color) como filtro opcional
input bool  NLMA_Rule1_HTFColor_FilterON        = false;   // usar color NonLag en HTF como filtro

// =================== Parámetros LRAC ===================
input double LRAC_MinWidthPips         = 20.0;     // LRAC - Ancho mínimo del canal
input double LRAC_MinSlopePips         = 2.0;      // LRAC - pendiente mínima (pips/bar) para considerar asc/desc
input int    LRAC_SlopeLookbackBars    = 5;        // LRAC - nº de barras para medir pendiente
input int    LRAC_HigherSteps          = 1;        // LRAC - N pasos TF superior (ej: de M1 a M15 = 3)

// =================== Parámetros NonLag HTF ===================
input int    NL_HTFHigherSteps         = 3;        // NL - pasos TF arriba para filtro con NonLag

// =================== TUS DOS FILTROS DE “ESPACIO” ===================
// [CHANGE] NUEVOS inputs para asegurar recorrido útil
input double MinCTF_DistOppPips        = 2.0;   // pips mínimos a banda opuesta en CTF
input double HTF_MinDistFromMidPct     = 0.15;  // % de ancho HTF que debe separarle de la mid

// =================== Debug / HUD ===================
input bool  EnableHUD                  = true;              // Mostrar/ocultar todo el HUD
input bool  DBG_ShowHUD                = true;              // Mostrar panel HUD
input ENUM_BASE_CORNER  DBG_HUDCorner  = CORNER_RIGHT_UPPER;// Esquina
input int   DBG_HUDX                   = 200;               // Desplazamiento X
input int   DBG_HUDY                   = 0;                 // Desplazamiento Y
input int   DBG_FontSize               = 9;                 // Tamaño fuente
input color DBG_TextColor              = clrWhite;          // Color texto
input color DBG_PanelGood              = clrLime;           // Color si OK
input color DBG_PanelBad               = clrOrangeRed;      // Color si NO

//--- Buffers
double NonLagBuffer[];   // Línea principal del indicador
double ColorBuffer[];    // Buffer de color del NonLag MA
double DownNLBuffer[];   // Flechas de venta
double UpNLBuffer[];     // Flechas de compra

double kBuffer[], dBuffer[];

int handleNonLag = INVALID_HANDLE;
int handleStoch = INVALID_HANDLE;
int handleLRAC_Cur = INVALID_HANDLE;
int handleLRAC_Htf = INVALID_HANDLE;
int handleNonLag_HTF = INVALID_HANDLE;  // opcional NonLag en HTF


// ========= TF mapping helpers (M1→M5→M15→M30→H1→H4→D1→W1→MN1) =========
ENUM_TIMEFRAMES TfFromSteps(ENUM_TIMEFRAMES base, int steps)
{
   static const ENUM_TIMEFRAMES ladder[] = {
      PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30,
      PERIOD_H1, PERIOD_H4, PERIOD_D1, PERIOD_W1, PERIOD_MN1
   };
   int pos=-1;
   for(int i=0;i<ArraySize(ladder);++i){ if(ladder[i]==base){ pos=i; break; } }
   if(pos<0) return base;
   int target = MathMin(ArraySize(ladder)-1, MathMax(0, pos+steps));
   return ladder[target];
}

string TfToStr(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:   return "M1";
      case PERIOD_M5:   return "M5";
      case PERIOD_M15:  return "M15";
      case PERIOD_M30:  return "M30";
      case PERIOD_H1:   return "H1";
      case PERIOD_H4:   return "H4";
      case PERIOD_D1:   return "D1";
      case PERIOD_W1:   return "W1";
      case PERIOD_MN1:  return "MN1";
      default:          return StringFormat("TF(%d)", (int)tf);
   }
}

// ---------- HUD helpers ----------

// Función de ejemplo para pintar una línea
void PutLine(string name, string text, int x, int y, color cText)
{
    if (ObjectFind(0, name) == -1)
        ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);

    ObjectSetInteger(0, name, OBJPROP_CORNER, DBG_HUDCorner);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, cText);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
    ObjectSetString(0, name, OBJPROP_FONT, "Tahoma");
    ObjectSetInteger(0, name, OBJPROP_BACK, false);
}   

void DelLines()
{
    int total_objects = ObjectsTotal(0, 0, -1);
    for (int i = total_objects - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i, 0, -1);
        if (StringFind(name, "line") == 0)
        {
            ObjectDelete(0, name);
        }
    }
}

// ---------- Init ----------
int OnInit()
{
   // Buffers
   SetIndexBuffer(0, NonLagBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, ColorBuffer, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, DownNLBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, UpNLBuffer, INDICATOR_DATA);

   // Flechas
   PlotIndexSetInteger(1, PLOT_ARROW, 234); // Sell: flecha abajo
   PlotIndexSetInteger(2, PLOT_ARROW, 233); // Buy : flecha arriba
   PlotIndexSetInteger(1, PLOT_LINE_WIDTH, 2);   
   PlotIndexSetInteger(2, PLOT_LINE_WIDTH, 2);
   
   // NonLag MTFi (línea + color)
   // Pasamos los parámetros según el orden esperado por el indicador:
   // 0 (frame code por defecto), periodo, precio, y opcionalmente
   // parámetro de interpolación.
   // Usamos NL_TimeFrame como timeframe de llamada en iCustom para
   // permitir ejecución en otros marcos de tiempo.
   handleNonLag = iCustom(_Symbol, NL_TimeFrame, "jmv-2025/NonLag_MA_mtfi", 0, NL_Period, NL_Price, NL_Interpolate);
   if(handleNonLag == INVALID_HANDLE)
   {
      Print("No se pudo crear el handle del NonLag MA mtf");
      return INIT_FAILED;
   }

   // Estocástico opcional   
   handleStoch = iStochastic(_Symbol, NL_TimeFrame, KPeriod, DPeriod, Slowing, MODE_SMA, 0);
   if(handleStoch == INVALID_HANDLE)
   {
      Print("No se pudo crear el handle del Estocástico");
      return INIT_FAILED;
   }
   
   // LRAC CTF (current timeframe)
   handleLRAC_Cur = iCustom(_Symbol, PERIOD_CURRENT,"jmv-2025/LinearRegression_Adaptive_Channel"
   );
   if(handleLRAC_Cur==INVALID_HANDLE){ Print("❌ LRAC CUR inválido"); return INIT_FAILED; }
   
   // LRAC HTF (higher timeframe)
   ENUM_TIMEFRAMES tfHTF = TfFromSteps(Period(), LRAC_HigherSteps);
   handleLRAC_Htf = iCustom(_Symbol, tfHTF,"jmv-2025/LinearRegression_Adaptive_Channel"
   );
   if(handleLRAC_Htf==INVALID_HANDLE){ Print("❌ LRAC HTF inválido"); return INIT_FAILED; }
   
   // NLMA HTF (opcional)
   if(NLMA_Rule1_HTFColor_FilterON)
   {
      ENUM_TIMEFRAMES nlTF = TfFromSteps(Period(), NL_HTFHigherSteps);
      handleNonLag_HTF = iCustom(_Symbol, nlTF, "jmv-2025/NonLag_MA_mtfi",
                                 0, NL_Period, NL_Price, NL_Interpolate);
      if(handleNonLag_HTF==INVALID_HANDLE){ Print("❌ NonLag HTF inválido"); return INIT_FAILED; }
   }
   
   // Mensajes de depuración TF
   PrintFormat("SIMN ▶ BaseTF=%s | LRAC_HigherSteps=%d → LRAC_HTF=%s",
               TfToStr(Period()), LRAC_HigherSteps, TfToStr(tfHTF));
   if(NLMA_Rule1_HTFColor_FilterON)
      PrintFormat("SIMN ▶ BaseTF=%s | NL_HTFHigherSteps=%d → NL_HTF=%s",
                  TfToStr(Period()), NL_HTFHigherSteps, TfToStr(TfFromSteps(Period(), NL_HTFHigherSteps)));

   return INIT_SUCCEEDED;
}

// ---------- Deinit ----------
void OnDeinit(const int reason)
{
   if(handleNonLag != INVALID_HANDLE) IndicatorRelease(handleNonLag);
   if(handleStoch != INVALID_HANDLE) IndicatorRelease(handleStoch);
   if(handleLRAC_Cur!=INVALID_HANDLE) IndicatorRelease(handleLRAC_Cur);
   if(handleLRAC_Htf!=INVALID_HANDLE) IndicatorRelease(handleLRAC_Htf);
   if(handleNonLag_HTF!=INVALID_HANDLE) IndicatorRelease(handleNonLag_HTF);
   
   DelLines();
}

// ---------- HUD globals ----------
double hud_widthPips = 0.0;
double hud_slopeCurPB = 0.0;
double hud_slopeHtfPB = 0.0;
int hud_dirCur = 0;
int hud_dirHtf = 0;
bool hud_lracOK = false;
bool hud_nlHtfOK = false;


// Función principal de cálculo
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
   // Necesitamos al menos 3 barras: (previa, cerrada, en formación)
   if(rates_total < 3) return prev_calculated;

   // NonLag buffers (línea+color)
   int nlCount = CopyBuffer(handleNonLag, 0, 0, rates_total, NonLagBuffer);
   int colCount = CopyBuffer(handleNonLag, 1, 0, rates_total, ColorBuffer);
   if (nlCount <= 0 || colCount <= 0) { Print("❌ NonLag_MA_mtfi sin datos"); return prev_calculated; }
   int maxAvailable = MathMin(nlCount, colCount);
   
   // Índice de la última barra cerrada 
   const int last_closed = rates_total - 2;
   const int first = MathMax(1, prev_calculated -1);
   const int last_i = MathMin(last_closed, maxAvailable - 1);
 
   // Subindicadores listos
   bool ready = (handleNonLag!=INVALID_HANDLE && BarsCalculated(handleNonLag)>0);
   if (UseStochasticFilter)
     ready = ready && (handleStoch!=INVALID_HANDLE && BarsCalculated(handleStoch)>0);
     
   const bool anyLRACRule =
      LRAC_FilterON && ( LRAC_Rule1_MinWidth
                      || LRAC_Rule2_CorrectBand
                      || LRAC_Rule2_UseTolerance
                      || LRAC_Rule3a_HTF_BandMatchesSignal
                      || LRAC_Rule3b_HTF_SlopeMatchesSignal
                      || LRAC_Rule3c_HTF_SlopeEqualsCTF
                      || LRAC_Rule4_HTF_Dominant
                      || LRAC_RequireTrendSide );
   
   if(anyLRACRule)
   {
      ready = ready && (handleLRAC_Cur!=INVALID_HANDLE && BarsCalculated(handleLRAC_Cur)>0);
   
      const bool needHTF_rules = (  LRAC_Rule3a_HTF_BandMatchesSignal
                                 || LRAC_Rule3b_HTF_SlopeMatchesSignal
                                 || LRAC_Rule3c_HTF_SlopeEqualsCTF
                                 || LRAC_Rule4_HTF_Dominant );
      if(needHTF_rules)
         ready = ready && (handleLRAC_Htf!=INVALID_HANDLE && BarsCalculated(handleLRAC_Htf)>0);
    
   }
   
   if (NLMA_Rule1_HTFColor_FilterON)
     ready = ready && (handleNonLag_HTF!=INVALID_HANDLE && BarsCalculated(handleNonLag_HTF)>0);
   
   if(!ready) return prev_calculated;

   // Estocástico opcional     
   if(UseStochasticFilter)
   {
      if(CopyBuffer(handleStoch, 0, 0, rates_total, kBuffer) <= 0 ||
         CopyBuffer(handleStoch, 1, 0, rates_total, dBuffer) <= 0)
         {
            Print("❌ Stoch sin datos"); 
            return prev_calculated;
         }
   }
   
   // TFs superiores precalculados
   ENUM_TIMEFRAMES tfLRAC_HTF = TfFromSteps(Period(), LRAC_HigherSteps);
   ENUM_TIMEFRAMES tfNL_HTF   = TfFromSteps(Period(), NL_HTFHigherSteps);
      
   // Limpia flechas a recalcular
   for (int i = first; i <= last_i; ++i){ UpNLBuffer[i]=EMPTY_VALUE; DownNLBuffer[i]=EMPTY_VALUE; }

   //int signalsTotal=0, signalsAccepted=0;
      
   // ===== Settings para SR_Evaluate =====
   SR_Settings S;
   S.LRAC_Rule1_MinWidth                = LRAC_Rule1_MinWidth;
   S.LRAC_Rule2_CorrectBand             = LRAC_Rule2_CorrectBand;
   S.LRAC_Rule3a_HTF_BandMatchesSignal  = LRAC_Rule3a_HTF_BandMatchesSignal;
   S.LRAC_Rule3b_HTF_SlopeMatchesSignal = LRAC_Rule3b_HTF_SlopeMatchesSignal;
   S.LRAC_Rule3c_HTF_SlopeEqualsCTF     = LRAC_Rule3c_HTF_SlopeEqualsCTF;
   S.LRAC_Rule4_HTF_Dominant            = LRAC_Rule4_HTF_Dominant;
   S.NLMA_Rule1_HTFColor_FilterON       = NLMA_Rule1_HTFColor_FilterON;
   
   S.LRAC_MinWidthPips                  = LRAC_MinWidthPips;
   S.LRAC_Rule2_UseTolerance            = LRAC_Rule2_UseTolerance;
   S.LRAC_Rule2_TolerancePct            = LRAC_Rule2_TolerancePct;
   S.LRAC_RequireTrendSide              = LRAC_RequireTrendSide;

   // [CHANGE] Aplica tus filtros de “espacio”
   S.MinCTF_DistOppPips                 = MinCTF_DistOppPips;
   S.HTF_MinDistFromMidPct              = HTF_MinDistFromMidPct;   

   // ========================== Bucle de señales ==========================
   for (int i = first; i <= last_i; ++i)
   {
      if(ColorBuffer[i] == EMPTY_VALUE || ColorBuffer[i-1] == EMPTY_VALUE)  continue;
      
      // Señal base por color NonLag + vela
      int currentColor = (int)ColorBuffer[i];
      int prevColor    = (int)ColorBuffer[i-1];
      bool isBuy  = (currentColor == 2 && prevColor != 2 && close[i] >= open[i]);
      bool isSell = (currentColor == 1 && prevColor != 1 && close[i] <= open[i]);
      if(!isBuy && !isSell) continue;

      //signalsTotal++;
      
      // Estocástico opcional
      if(UseStochasticFilter)
      {
         const double k=kBuffer[i], d=dBuffer[i];
         const bool stochOK = (isBuy ? (k>d && k<30) : (k<d && k>70));
         if(!stochOK) continue;
      }
      
      // ----- Inputs para evaluador
      SR_Inputs I; ZeroMemory(I);
      I.isBuy  = isBuy;
      I.isSell = isSell;
      
      // ¿Necesitamos CTF/HTF?
      const bool needCTF_rules = anyLRACRule && (  LRAC_Rule1_MinWidth
                                                || LRAC_Rule2_CorrectBand
                                                || LRAC_Rule3c_HTF_SlopeEqualsCTF );
      const bool needCTF_extra = anyLRACRule && ( LRAC_Rule2_UseTolerance || LRAC_RequireTrendSide);
      const bool needCTF       = needCTF_rules || needCTF_extra;

      const bool needHTF_rules = anyLRACRule && (  LRAC_Rule3a_HTF_BandMatchesSignal
                                                || LRAC_Rule3b_HTF_SlopeMatchesSignal
                                                || LRAC_Rule3c_HTF_SlopeEqualsCTF
                                                || LRAC_Rule4_HTF_Dominant );

      // ---------- CTF (LRAC CUR) ----------
      if(needCTF && handleLRAC_Cur!=INVALID_HANDLE /* && BarsCalculated(handleLRAC_Cur)>0 */)
      {
         int sh     = (rates_total - 1) - i;              // índice barra cerrada exacto
         int shPrev = sh + LRAC_SlopeLookbackBars;
         if(sh<0 || shPrev<0) continue;
         
         double upCur[1], loCur[1], midNow[1], midPrev[1];
         bool okCTF = (CopyBuffer(handleLRAC_Cur,0,sh,1,upCur)==1) &&
                      (CopyBuffer(handleLRAC_Cur,1,sh,1,loCur)==1) &&
                      (CopyBuffer(handleLRAC_Cur,2,sh,1,midNow)==1) &&
                      (CopyBuffer(handleLRAC_Cur,2,shPrev,1,midPrev)==1) &&
                      (upCur[0]!=EMPTY_VALUE && loCur[0]!=EMPTY_VALUE &&
                       midNow[0]!=EMPTY_VALUE && midPrev[0]!=EMPTY_VALUE);
         if(!okCTF) continue;

         const double slopeCurPB = (midNow[0]-midPrev[0])/_Point/LRAC_SlopeLookbackBars;
         const int dirCurInt     = (MathAbs(slopeCurPB) < LRAC_MinSlopePips) ? 0 : (slopeCurPB>0 ? 1 : -1);
         const double widthCTFpx = (upCur[0]-loCur[0]);
         const double midCTF     = midNow[0];

         I.widthPipsCTF  = widthCTFpx/_Point;
         I.inLowerCTF    = (close[i] <= midCTF);
         I.dirCTF        = (dirCurInt>0 ? SR_UP : (dirCurInt<0 ? SR_DOWN : SR_FLAT));
         I.priceCTF      = close[i];
         I.midCTF        = midCTF;
         I.widthPriceCTF = widthCTFpx;
         I.upCTF          = upCur[0];        // bandas CTF para filtro de distancia
         I.loCTF          = loCur[0];         
      }
      
      
      // ---------- HTF (LRAC HTF) ----------
      if(needHTF_rules && handleLRAC_Htf!=INVALID_HANDLE)
      {
         // alineamos al **cierre** de la barra CTF i
         int htfShift0 = iBarShift(_Symbol, tfLRAC_HTF, time[i], false);
         if(htfShift0<0) continue;

         double midNowHTF[1], midPrevHTF[1];
         bool okPend = (CopyBuffer(handleLRAC_Htf,2,htfShift0,1,midNowHTF)==1) &&
                       (CopyBuffer(handleLRAC_Htf,2,htfShift0+LRAC_SlopeLookbackBars,1,midPrevHTF)==1) &&
                       (midNowHTF[0]!=EMPTY_VALUE && midPrevHTF[0]!=EMPTY_VALUE);
         if(!okPend) continue;

         const double slopeHtfPB = (midNowHTF[0]-midPrevHTF[0])/_Point/LRAC_SlopeLookbackBars;
         const int    dirHtfInt  = (MathAbs(slopeHtfPB) < LRAC_MinSlopePips) ? 0 : (slopeHtfPB>0 ? 1 : -1);

         double upH[1], loH[1], cH[1];
         bool okBands = (CopyBuffer(handleLRAC_Htf,0,htfShift0,1,upH)==1 && upH[0]!=EMPTY_VALUE &&
                         CopyBuffer(handleLRAC_Htf,1,htfShift0,1,loH)==1 && loH[0]!=EMPTY_VALUE);
         bool okClose = (CopyClose(_Symbol, tfLRAC_HTF, htfShift0, 1, cH)==1);

         if(!(okBands && okClose)) continue;

         I.haveHTF        = true;
         I.dirHTF         = (dirHtfInt>0 ? SR_UP : (dirHtfInt<0 ? SR_DOWN : SR_FLAT));
         I.priceHTF       = cH[0];
         I.midHTF         = midNowHTF[0];
         I.upHTF          = upH[0];          // bandas HTF para tu 2º filtro
         I.loHTF          = loH[0];
         I.widthPriceHTF  = (upH[0]-loH[0]);
         I.inLowerHTF     = (I.priceHTF <= I.midHTF);
      }      

      // ---------- NLMA HTF color (opcional) ----------
      I.haveNLHTF=false; I.nlColorHTF=0;
      if(NLMA_Rule1_HTFColor_FilterON && handleNonLag_HTF!=INVALID_HANDLE)
      {
         int htfShift = iBarShift(_Symbol, tfNL_HTF, time[i], false);
         if(htfShift>=0)
         {
            double col[1];
            if(CopyBuffer(handleNonLag_HTF,1,htfShift,1,col)==1)
            { I.haveNLHTF=true; I.nlColorHTF=(int)col[0]; }
         }
      }
   
      
      // ---------- Evaluación centralizada ----------
      const bool rulesEnabled = (LRAC_FilterON || NLMA_Rule1_HTFColor_FilterON);
      bool pass = (!rulesEnabled) ? true : SR_Evaluate(S, I).passAll;
      
      /*                              
      if(rulesEnabled && !pass){
         PrintFormat("SR_FAIL i=%d buy=%d sell=%d width=%.1f dir=%d inLower=%d",
                     i, isBuy, isSell, I.widthPipsCTF, (int)I.dirCTF, (int)I.inLowerCTF);
      }
      */      
                                    
      // ---------- Pintado de flechas ----------
      if(pass) 
      {
         if (isBuy)  UpNLBuffer[i]   = close[i] + Arrows_Offset * _Point;
         if (isSell) DownNLBuffer[i] = close[i] - Arrows_Offset * _Point;
         //signalsAccepted++;
      }
   } // fin bucle for i

   // ============================== HUD ======================================
   if(EnableHUD)
   {
      int lastBar = rates_total - 2;
      if(lastBar < 1) lastBar = 1;

      bool hudSigBuy  = (UpNLBuffer[lastBar]   != EMPTY_VALUE);
      bool hudSigSell = (DownNLBuffer[lastBar] != EMPTY_VALUE);

      // Reset
      hud_widthPips=0.0; hud_slopeCurPB=0.0; hud_slopeHtfPB=0.0;
      hud_dirCur=0; hud_dirHtf=0;
      hud_lracOK=false;
      hud_nlHtfOK = (handleNonLag_HTF!=INVALID_HANDLE ? false : true);

      // Métricas LRAC
      if(handleLRAC_Cur!=INVALID_HANDLE && handleLRAC_Htf!=INVALID_HANDLE)
      {
         double upCur[1], loCur[1];
         if (CopyBuffer(handleLRAC_Cur, 0, 1, 1, upCur)==1 && upCur[0]!=EMPTY_VALUE &&
             CopyBuffer(handleLRAC_Cur, 1, 1, 1, loCur)==1 && loCur[0]!=EMPTY_VALUE)
            hud_widthPips = (upCur[0]-loCur[0])/_Point;

         double midNow[1], midPrev[1];
         bool okNow =(CopyBuffer(handleLRAC_Cur,2,1,1,midNow)==1);
         bool okPrv =(CopyBuffer(handleLRAC_Cur,2,1+LRAC_SlopeLookbackBars,1,midPrev)==1);
         if(okNow && okPrv && midNow[0]!=EMPTY_VALUE && midPrev[0]!=EMPTY_VALUE)
         {
            hud_slopeCurPB=(midNow[0]-midPrev[0])/_Point/LRAC_SlopeLookbackBars;
            hud_dirCur=(MathAbs(hud_slopeCurPB)<LRAC_MinSlopePips?0:(hud_slopeCurPB>0?1:-1));

            int htfShift_now=iBarShift(_Symbol, tfLRAC_HTF, time[rates_total-1], false);
            if(htfShift_now>=0)
            {
               double mH[1], mHp[1];
               bool okH =(CopyBuffer(handleLRAC_Htf,2,htfShift_now,1,mH)==1);
               bool okHp=(CopyBuffer(handleLRAC_Htf,2,htfShift_now+LRAC_SlopeLookbackBars,1,mHp)==1);
               if(okH && okHp && mH[0]!=EMPTY_VALUE && mHp[0]!=EMPTY_VALUE)
               {
                  hud_slopeHtfPB=(mH[0]-mHp[0])/_Point/LRAC_SlopeLookbackBars;
                  hud_dirHtf=(MathAbs(hud_slopeHtfPB)<LRAC_MinSlopePips?0:(hud_slopeHtfPB>0?1:-1));
                  hud_lracOK=true;
               }
            }
         }
      }

      // NLMA HTF en HUD
      if(handleNonLag_HTF!=INVALID_HANDLE)
      {
         int htfIndex = iBarShift(_Symbol, tfNL_HTF, time[lastBar], false);
         if(htfIndex>=0)
         {
            double col[1];
            if(CopyBuffer(handleNonLag_HTF, 1, htfIndex, 1, col)==1)
            {
               int c=(int)col[0]; // 0 gris, 1 rosa, 2 verde
               hud_nlHtfOK = ( (hudSigBuy && c==2) || (hudSigSell && c==1) );
            }
         }
      }

      string sdirCur = (hud_dirCur>0?"UP":(hud_dirCur<0?"DOWN":"FLAT"));
      string sdirHtf = (hud_dirHtf>0?"UP":(hud_dirHtf<0?"DOWN":"FLAT"));
      string sSig    = hudSigBuy ? "BUY" : (hudSigSell ? "SELL" : "—");

      PutLine("line1", "LRAC:", DBG_HUDX, DBG_HUDY + 10, clrWhite);
      PutLine("line2", StringFormat(" signal: %s", sSig), DBG_HUDX, DBG_HUDY + 25, clrWhite);
      PutLine("line3", StringFormat(" width: %.1f pips", hud_widthPips), DBG_HUDX, DBG_HUDY + 40, clrWhite);
      PutLine("line4", StringFormat(" cur: %s (%.2f pips/b)", sdirCur, hud_slopeCurPB), DBG_HUDX, DBG_HUDY + 55, clrWhite);
      PutLine("line5", StringFormat(" htf: %s (%.2f pips/b)", sdirHtf, hud_slopeHtfPB), DBG_HUDX, DBG_HUDY + 70, clrWhite);
      PutLine("line6", StringFormat(" OK: LRAC=%s | NLhtf=%s",
                hud_lracOK?"Y":"N", hud_nlHtfOK?"Y":"N"), DBG_HUDX, DBG_HUDY + 85, clrWhite);
   }
   else
   {
      DelLines();
   }
   
   // -----------------------------------------------------------------------
   
   //Print("Señales totales: ", signalsTotal, ", aceptadas tras filtro: ", signalsAccepted);
   return rates_total;
}