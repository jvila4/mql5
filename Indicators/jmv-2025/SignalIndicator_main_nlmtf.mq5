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

#property copyright "Copyright 2025, JmVila"
#property link      "https://www.mql5.com"
#property version   "1.00"

#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   3

// Configuración de plot de linea de indicador principal
#property indicator_label1  "NonLag MA Line"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrDarkGray,clrDeepPink,clrLimeGreen
#property indicator_width1  2

// Configuración de plot de flechas de compra
#property indicator_label2  "Sell_NL_Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrDeepPink
#property indicator_width2  2

// Configuración de plot de flechas de venta
#property indicator_label3  "Buy_NL_Signal"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrLimeGreen
#property indicator_width3  2

// Parámetros de entrada para el NonLag MA mtf
input ENUM_TIMEFRAMES NL_TimeFrame = PERIOD_CURRENT;    // Time frame del NonLag MA
input double          NL_Period    = 12;                // Periodo del NonLag MA, default 27
input ENUM_APPLIED_PRICE NL_Price  = PRICE_WEIGHTED;    // Precio aplicado
input bool            NL_Interpolate = true;            // Interpolación en modo MTF

input int    CanalPeriod = 40;                 // Periodo para canal sobre NonLagBuffer
input double CanalWidthMultiplier = 1.5;        // Multiplicador de la desviación estándar
input double CanalMarginRatio = 0.1;            // Ratio del canal desde el borde donde evitar señales

input int Arrows_Offset = 5;              // Offset de flechas


input bool UseStochasticFilter = false;  // Activar filtro estocástico
input int KPeriod = 5;
input int DPeriod = 3;
input int Slowing = 3;

// === Control de activación de filtros
input bool  LRAC_FilterON              = false;    // LRAC - Activar filtro
// === Reglas de filtrado LRAC independientes ===
input bool  LRAC_Rule1_MinWidth        = true;     // LRAC Regla 1: ancho mínimo del canal
input bool  LRAC_Rule2_CorrectBand     = true;     // LRAC Regla 2: mitad correcta del canal
// === Reglas LRAC (nuevas sub-reglas 3a/3b/3c) ===
input bool  LRAC_Rule3a_HTF_BandMatchesSignal  = true;  // 3a: zona/mitad HTF compatible con la señal
input bool  LRAC_Rule3b_HTF_SlopeMatchesSignal = true;  // 3b: pendiente HTF compatible con la señal (±1)
input bool  LRAC_Rule3c_HTF_SlopeEqualsCTF     = false; // 3c: pendiente HTF igual a CTF (incluye FLAT)

input bool  LRAC_Rule4_HTF_Dominant    = true;     // LRAC Regla 4: HTF dominante (solo compra si HTF alcista, etc.)
input bool  NL_HTFColor_FilterON       = false;    // Requiere color NonLag en HTF
input bool  EnableHUD                  = true;     // Mostrar/ocultar todo el HUD

// === Parámetros de LRAC ===
input double LRAC_MinWidthPips         = 20.0;     // LRAC - Ancho mínimo del canal
input double LRAC_MinSlopePips         = 2.0;      // LRAC - pendiente mínima (pips/bar) para considerar asc/desc
input int    LRAC_SlopeLookbackBars    = 5;        // LRAC - nº de barras para medir pendiente
input int    LRAC_HigherSteps          = 1;        // LRAC - N pasos TF superior (ej: de M1 a M15 = 3)

// === Parámetros de NonLag_MA en HTF ===
input int    NL_HTFHigherSteps         = 3;        // NL - pasos TF arriba para filtro con NonLag

// === Debug / Overlay ===
input bool            DBG_ShowHUD   = true;               // Mostrar panel HUD
input ENUM_BASE_CORNER DBG_HUDCorner = CORNER_RIGHT_UPPER;// Esquina
input int             DBG_HUDX      = 200;                 // Desplazamiento X
input int             DBG_HUDY      = 0;                 // Desplazamiento Y
input int             DBG_FontSize  = 9;                  // Tamaño fuente
input color           DBG_TextColor = clrWhite;           // Color texto
input color           DBG_PanelGood = clrLime;            // Color si OK
input color           DBG_PanelBad  = clrOrangeRed;       // Color si NO


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

// Mapa simple de pasos (M1→M5→M15→M30→H1→H4→D1→W1→MN1)
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

enum LRAC_DIR { LRAC_FLAT=0, LRAC_UP=1, LRAC_DOWN=-1 };

// ---------- Helpers de UI Debug ----------

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

// Inicialización
int OnInit()
{
   // Asignar buffers
   SetIndexBuffer(0, NonLagBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, ColorBuffer, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, DownNLBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, UpNLBuffer, INDICATOR_DATA);

   //s Configurar flechas (códigos Wingdings: 233 arriba, 234 abajo)
   PlotIndexSetInteger(1, PLOT_ARROW, 234); // Venta: flecha abajo
   PlotIndexSetInteger(2, PLOT_ARROW, 233); // Compra: flecha arriba  
   PlotIndexSetInteger(1, PLOT_LINE_WIDTH, 2);   
   PlotIndexSetInteger(2, PLOT_LINE_WIDTH, 2);
   
   // Crear handle del indicador NonLag MA mtf
   // Pasamos los parámetros según el orden esperado por el indicador:
   // 0 (frame code por defecto), periodo, precio, y opcionalmente
   // parámetro de interpolación.
   // Usamos NL_TimeFrame como timeframe de llamada en iCustom para
   // permitir ejecución en otros marcos de tiempo.
   handleNonLag = iCustom(_Symbol, NL_TimeFrame, "NonLag_MA_mtfi", 0, NL_Period, NL_Price, NL_Interpolate);
   if(handleNonLag == INVALID_HANDLE)
   {
      Print("No se pudo crear el handle del NonLag MA mtf");
      return INIT_FAILED;
   }
   
   handleStoch = iStochastic(_Symbol, NL_TimeFrame, KPeriod, DPeriod, Slowing, MODE_SMA, 0);
   if(handleStoch == INVALID_HANDLE)
   {
      Print("No se pudo crear el handle del Estocástico");
      return INIT_FAILED;
   }
   
   // --- LRAC en TF actual ---
   handleLRAC_Cur = iCustom(
      _Symbol, PERIOD_CURRENT, 
      "LinearRegression_Adaptive_Channel"
   );
   if(handleLRAC_Cur==INVALID_HANDLE){ Print("❌ LRAC CUR inválido"); return INIT_FAILED; }
   
   // --- LRAC en TF superior ---
   ENUM_TIMEFRAMES tfHTF = TfFromSteps(Period(), LRAC_HigherSteps);
   handleLRAC_Htf = iCustom(
      _Symbol, tfHTF,
      "LinearRegression_Adaptive_Channel"
   );
   if(handleLRAC_Htf==INVALID_HANDLE){ Print("❌ LRAC HTF inválido"); return INIT_FAILED; }
   
   // --- NonLag en HTF (opcional punto 4) ---
   if(NL_HTFColor_FilterON){
      ENUM_TIMEFRAMES nlTF = TfFromSteps(Period(), NL_HTFHigherSteps);
      handleNonLag_HTF = iCustom(_Symbol, nlTF, "NonLag_MA_mtfi", 0, NL_Period, NL_Price, NL_Interpolate);
      if(handleNonLag_HTF==INVALID_HANDLE){ Print("❌ NonLag HTF inválido"); return INIT_FAILED; }
   }
   
   // 👉 Debug: imprime los HTF elegidos
   PrintFormat("SIMN ▶ BaseTF=%s | LRAC_HigherSteps=%d → LRAC_HTF=%s",
               TfToStr(Period()), LRAC_HigherSteps, TfToStr(tfHTF));
   if(NL_HTFColor_FilterON)
      PrintFormat("SIMN ▶ BaseTF=%s | NL_HTFHigherSteps=%d → NL_HTF=%s",
                  TfToStr(Period()), NL_HTFHigherSteps,
                  TfToStr(TfFromSteps(Period(), NL_HTFHigherSteps)));

   return INIT_SUCCEEDED;
}

// Liberación
void OnDeinit(const int reason)
{
   if(handleNonLag != INVALID_HANDLE) IndicatorRelease(handleNonLag);
   if(handleStoch != INVALID_HANDLE) IndicatorRelease(handleStoch);
   if(handleLRAC_Cur!=INVALID_HANDLE) IndicatorRelease(handleLRAC_Cur);
   if(handleLRAC_Htf!=INVALID_HANDLE) IndicatorRelease(handleLRAC_Htf);
   if(handleNonLag_HTF!=INVALID_HANDLE) IndicatorRelease(handleNonLag_HTF);
   
   DelLines();
}

// --- Variables globales para el HUD ---
double hud_widthPips = 0.0;
double hud_slopeCurPB = 0.0;
double hud_slopeHtfPB = 0.0;
int hud_dirCur = 0;
int hud_dirHtf = 0;
bool hud_lracOK = false;
bool hud_nlHtfOK = false;
bool hud_isBuy = false;
bool hud_isSell = false;

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

   // --- NonLag base (línea + color)
   int nlCount = CopyBuffer(handleNonLag, 0, 0, rates_total, NonLagBuffer);
   int colCount = CopyBuffer(handleNonLag, 1, 0, rates_total, ColorBuffer);
   if (nlCount <= 0 || colCount <= 0)
   {
      Print("❌ No se pudieron copiar los buffers desde NonLag_MA_mtfi");
      return prev_calculated;
   }
   int maxAvailable = MathMin(nlCount, colCount);
   

   // Índice de la última barra cerrada 
   const int last_closed = rates_total - 2;

   // Recalcular 1 barra hacia atras para estabilidad y evitar re-pintados
   //const int first = (prev_calculated == 0) ? 1 : last_closed;
   const int first = MathMax(1, prev_calculated -1);
   const int last_i = MathMin(last_closed, maxAvailable - 1);

 
   // --- Asegurar sub-indicadores listos ---
   bool ready = true;
   
   // Siempre: NonLag base
   ready &= (handleNonLag!=INVALID_HANDLE && BarsCalculated(handleNonLag)>0);
   
   // Opcional: Stoch
   if (UseStochasticFilter)
     ready &= (handleStoch!=INVALID_HANDLE && BarsCalculated(handleStoch)>0);
   
   // Opcional: LRAC (CTF y HTF) SOLO si vas a usar LRAC
   if (LRAC_FilterON) {
     ready &= (handleLRAC_Cur!=INVALID_HANDLE && BarsCalculated(handleLRAC_Cur)>0);
     ready &= (handleLRAC_Htf!=INVALID_HANDLE && BarsCalculated(handleLRAC_Htf)>0);
   }
   
   // Opcional: NonLag HTF SOLO si lo pides
   if (NL_HTFColor_FilterON)
     ready &= (handleNonLag_HTF!=INVALID_HANDLE && BarsCalculated(handleNonLag_HTF)>0);
   
   if(!ready) return prev_calculated;
      

   // --- Filtro con Estocástico (opcional)      
   if(UseStochasticFilter)
   {
      if(CopyBuffer(handleStoch, 0, 0, rates_total, kBuffer) <= 0 ||
         CopyBuffer(handleStoch, 1, 0, rates_total, dBuffer) <= 0)
         {
            Print("❌ No se pudieron copiar los buffers desde handleStoch");
            return prev_calculated;
         }
   }
   
   //const int last = rates_total - 1;
   //const int begin = (prev_calculated > 1) ? prev_calculated - 1 : 1;
   const int PROBE_MAX = 50; // nº máx. de velas HTF a probar hacia el pasado (shift creciente)

   // TFs superiores precalculados
   ENUM_TIMEFRAMES tfLRAC_HTF = TfFromSteps(Period(), LRAC_HigherSteps);
   ENUM_TIMEFRAMES tfNL_HTF   = TfFromSteps(Period(), NL_HTFHigherSteps);
   
   // Limpia slots que vayamos a recalcular (flechas)
   for (int i = first; i <= last_i; ++i)
   {
      UpNLBuffer[i]   = EMPTY_VALUE;
      DownNLBuffer[i] = EMPTY_VALUE;
      //NonLagBuffer[i] = EMPTY_VALUE;
      //ColorBuffer[i]  = EMPTY_VALUE;
   }
   
   int signalsTotal    = 0;
   int signalsAccepted = 0;
   
   // ========================== BUCLE DE SEÑALES =============================
   for (int i = first; i <= last_i; ++i)
   {
      if(ColorBuffer[i] == EMPTY_VALUE || ColorBuffer[i-1] == EMPTY_VALUE)
         continue;
      
      // Señal base por color NonLag + vela
      int currentColor = (int)ColorBuffer[i];
      int prevColor    = (int)ColorBuffer[i-1];
      bool isBuy  = (currentColor == 2 && prevColor != 2 && close[i] >= open[i]);
      bool isSell = (currentColor == 1 && prevColor != 1 && close[i] <= open[i]);
      
      // Filtro estocástico (si procede)
      bool stochOK = true;
      if(UseStochasticFilter)
      {
         double k = kBuffer[i];
         double d = dBuffer[i];
         // Personalizar la condición según criterio (ej: cruce ascendente o zona de sobreventa)
         stochOK = (k > d && k < 30) || (k < d && k > 70);  // ejemplo simple
      }
      
      // --- Filtro LRAC CUR + HTF (si procede) ---
      bool passRule1 = true, passRule2 = true, passRule3a = true, passRule3b = true, passRule3c = true, passRule4 = true;

                  
      if(LRAC_FilterON)
      {
         // Convertimos índice "i" (no-serie) a shift (serie)
         const int sh     = last_closed - i;                 // 0=actual, 1=cerrada, ...
         const int shPrev = sh + LRAC_SlopeLookbackBars;     // más antigua = shift mayor        // TF actual
         
         double upCur[1], loCur[1], midNow[1], midPrev[1];
         bool ok = (CopyBuffer(handleLRAC_Cur,0,sh,1,upCur)==1) &&
                   (CopyBuffer(handleLRAC_Cur,1,sh,1,loCur)==1) &&
                   (CopyBuffer(handleLRAC_Cur,2,sh,1,midNow)==1) &&
                   (CopyBuffer(handleLRAC_Cur,2,shPrev,1,midPrev)==1);
         
         if(ok && upCur[0]!=EMPTY_VALUE && loCur[0]!=EMPTY_VALUE &&
            midNow[0]!=EMPTY_VALUE && midPrev[0]!=EMPTY_VALUE)
         {
            double widthPips   = (upCur[0]-loCur[0])/_Point;
            double slopeCurPB  = (midNow[0]-midPrev[0])/_Point/LRAC_SlopeLookbackBars;
            int dirCurInt      = (MathAbs(slopeCurPB) < LRAC_MinSlopePips) ? 0 : (slopeCurPB>0 ? 1 : -1);
            bool inLower       = (close[i] <= midNow[0]);
            bool inUpper       = !inLower;
            
            // ¿Necesitamos datos HTF por alguna regla?
            bool needHTF = (LRAC_Rule3a_HTF_BandMatchesSignal  ||
                            LRAC_Rule3b_HTF_SlopeMatchesSignal ||
                            LRAC_Rule3c_HTF_SlopeEqualsCTF     ||
                            LRAC_Rule4_HTF_Dominant); // ya la usabas            
            
            // === Buscar dirección HTF ===
            int dirHtfInt = 0;
            bool okHTF = false;
            double midNowHTF = 0.0, midPrevHTF = 0.0;
            
            // Sólo si los necesitamos:
            int htfShift0 = -1;  // <-- Mover la declaración aquí (fuera del if)
            if (needHTF) {
               // iBarShift con exact=false para evitar -1 entre velas
               htfShift0 = iBarShift(_Symbol, tfLRAC_HTF, time[i], false);
               
               if(htfShift0>=0)
               {
                  double midNowHTF_a[1], midPrevHTF_a[1];
                  if(CopyBuffer(handleLRAC_Htf,2,htfShift0,1,midNowHTF_a)==1 &&
                     CopyBuffer(handleLRAC_Htf,2,htfShift0+LRAC_SlopeLookbackBars,1,midPrevHTF_a)==1 &&
                     midNowHTF_a[0]!=EMPTY_VALUE && midPrevHTF_a[0]!=EMPTY_VALUE)
                  {
                      midNowHTF = midNowHTF_a[0];
                      midPrevHTF = midPrevHTF_a[0];
                      double slopeHtfPB = (midNowHTF-midPrevHTF)/_Point/LRAC_SlopeLookbackBars;
                      dirHtfInt = (MathAbs(slopeHtfPB) < LRAC_MinSlopePips) ? 0 : (slopeHtfPB>0 ? 1 : -1);
                      okHTF = true;
                  }
               }
            }
            
            //  MITADES HTF (para 3a)
            bool okCloseHTF=false, inLowerHTF=false, inUpperHTF=false;
            if (okHTF)
            {
               double htfClose[1];
               okCloseHTF = (CopyClose(_Symbol, tfLRAC_HTF, htfShift0, 1, htfClose) == 1);
               if (okCloseHTF) {
                  inLowerHTF = (htfClose[0] <= midNowHTF);
                  inUpperHTF = !inLowerHTF;
               }
            }
            
            // ------------------ APLICACIÓN DE REGLAS de FILTRO LRAC ------------------
            // Regla 1: ancho mínimo
            if(LRAC_Rule1_MinWidth)
            {
                passRule1 = (widthPips >= LRAC_MinWidthPips);
            }
            
            // Regla 2: mitad correcta en CTF
            if(LRAC_Rule2_CorrectBand)
            {
               if(isBuy)  passRule2 = inLower;
               if(isSell) passRule2 = inUpper;
            }
            
            // Regla 3a: zona (mitad) HTF compatible con la señal (requiere okHTF y okCloseHTF)
            if (LRAC_Rule3a_HTF_BandMatchesSignal) {
               passRule3a = okHTF && okCloseHTF && ( (isBuy  && inLowerHTF) ||
                                                     (isSell && inUpperHTF) );
            }
            
            // Regla 3b: pendiente HTF compatible con la señal (requiere okHTF)
            if (LRAC_Rule3b_HTF_SlopeMatchesSignal) {
               passRule3b = okHTF && ( (isBuy  && dirHtfInt ==  1) ||
                                       (isSell && dirHtfInt == -1) );
            }
            
            // Regla 3c: pendiente HTF igual a CTF (incluye FLAT=0)
            if (LRAC_Rule3c_HTF_SlopeEqualsCTF) {
               passRule3c = okHTF && (dirHtfInt == dirCurInt);
            }            
                        
            // Regla 4: HTF dominante (la que ya tenías)      
            if (LRAC_Rule4_HTF_Dominant && needHTF) {
               if (okHTF) {
                  if (dirHtfInt ==  1) passRule4 = isBuy;
                  if (dirHtfInt == -1) passRule4 = isSell;
                  // si dirHtfInt==0 (flat) ⇒ bloquea ambas al activar esta regla
                  if (dirHtfInt ==  0) passRule4 = false;
               } else {
                  passRule4 = false;
               }
            }
         }
         else
         {
            passRule1=passRule2=passRule3a=passRule3b=passRule3c=passRule4=false;
         }
      }
      
      // --------------- Filtro NL en HTF (opcional) ---------------
      bool nlAlignOK = false;
      if(NL_HTFColor_FilterON){
         const datetime ti = time[i];
         //const int htfShift = iBarShift(_Symbol, tfNL_HTF, ti);
         const int htfShift = iBarShift(_Symbol, tfNL_HTF, ti, false);
         if(htfShift < 0) nlAlignOK = false;
         else{
            double col[1];
            if(CopyBuffer(handleNonLag_HTF, 1, htfShift, 1, col) != 1) nlAlignOK = false;
            else
            {
               const int c = (int)col[0]; // 0 gris, 1 rosa, 2 verde
               if(isBuy)  nlAlignOK = (c==2);
               if(isSell) nlAlignOK = (c==1);
            }
         }
      }
 
      // --- Decisión final: Pintado de flechas si pasa todos los filtros ---         
      bool passAll = stochOK
                     && (!LRAC_FilterON || (passRule1 && passRule2 && passRule3a && passRule3b && passRule3c && passRule4))
                     && (!NL_HTFColor_FilterON || nlAlignOK);
      
      if (isBuy && passAll) {
          UpNLBuffer[i] = close[i] + Arrows_Offset * _Point;
          // signalsAccepted++;
      } else if (isSell && passAll) {
          DownNLBuffer[i] = close[i] - Arrows_Offset * _Point;
          // signalsAccepted++;
      }
   } // fin bucle for i
   
   
   // ============================== HUD ======================================
   // ================= HUD (calcula SIEMPRE, aunque LRAC_FilterON=false) =================
   if(EnableHUD)
   {
      //int lastBar = 1;                               // última cerrada
      //if(lastBar >= rates_total) lastBar = rates_total - 1;
      
      int lastBar = rates_total - 2;   // última cerrada real
      if (lastBar < 1) lastBar = 1;      
      
      // Señal del HUD basada en lo que realmente se pintó
      bool hudSigBuy  = (UpNLBuffer[lastBar]   != EMPTY_VALUE);
      bool hudSigSell = (DownNLBuffer[lastBar] != EMPTY_VALUE);
      
      // Reset
      hud_widthPips = 0.0;
      hud_slopeCurPB = 0.0;
      hud_slopeHtfPB = 0.0;
      hud_dirCur = 0;
      hud_dirHtf = 0;
      hud_lracOK = false;        // "tenemos datos LRAC válidos"
      hud_nlHtfOK = (handleNonLag_HTF!=INVALID_HANDLE ? false : true); // si no hay handle, lo marcamos como no-aplica
      
      // --- Métricas LRAC (CUR & HTF) SIEMPRE que haya handles válidos ---
      if(handleLRAC_Cur!=INVALID_HANDLE && handleLRAC_Htf!=INVALID_HANDLE)
      {
         // 1. Ancho actual
         double upCur[1], loCur[1];
         if (CopyBuffer(handleLRAC_Cur, 0, 1, 1, upCur) == 1 && upCur[0] != EMPTY_VALUE &&
            CopyBuffer(handleLRAC_Cur, 1, 1, 1, loCur) == 1 && loCur[0] != EMPTY_VALUE)
         {
            hud_widthPips = (upCur[0] - loCur[0]) / _Point;
         }
         
         // 2. Pendiente CTF
         double midCur_i[1], midCur_prev[1];
         bool okMidNow = CopyBuffer(handleLRAC_Cur, 2, 1, 1, midCur_i) == 1;
         bool okMidPrev = CopyBuffer(handleLRAC_Cur, 2, 1 + LRAC_SlopeLookbackBars, 1, midCur_prev) == 1;
         
         if (okMidNow && okMidPrev && midCur_i[0] != EMPTY_VALUE && midCur_prev[0] != EMPTY_VALUE)
         {
            hud_slopeCurPB = (midCur_i[0] - midCur_prev[0]) / _Point / LRAC_SlopeLookbackBars;
            hud_dirCur = (MathAbs(hud_slopeCurPB) < LRAC_MinSlopePips) ? 0 : (hud_slopeCurPB > 0 ? 1 : -1);
         
            // 3. Pendiente HTF
            datetime time_now = time[rates_total - 1]; // Tiempo de la barra más reciente
            int htfShift_now = iBarShift(_Symbol, tfLRAC_HTF, time_now, false); 
            if (htfShift_now >= 0)
            {
                double midH_now[1], midH_prev[1];
                bool okHnow = (CopyBuffer(handleLRAC_Htf, 2, htfShift_now, 1, midH_now) == 1);
                bool okHprev = (CopyBuffer(handleLRAC_Htf, 2, htfShift_now + LRAC_SlopeLookbackBars, 1, midH_prev) == 1);
                
                if (okHnow && okHprev && midH_now[0] != EMPTY_VALUE && midH_prev[0] != EMPTY_VALUE)
                {
                    hud_slopeHtfPB = (midH_now[0] - midH_prev[0]) / _Point / LRAC_SlopeLookbackBars;
                    hud_dirHtf = (MathAbs(hud_slopeHtfPB) < LRAC_MinSlopePips) ? 0 : (hud_slopeHtfPB > 0 ? 1 : -1);
                    hud_lracOK = true;
                }
            }
         }
      }
      
      // --- Alineación NonLag en HTF para HUD (si hay handle disponible) ---
      if(handleNonLag_HTF!=INVALID_HANDLE)
      {
         ENUM_TIMEFRAMES tfNL_HTF2 = TfFromSteps(Period(), NL_HTFHigherSteps);
         datetime ti = time[lastBar];
         int htfIndex = iBarShift(_Symbol, tfNL_HTF2, ti, false);
         if(htfIndex>=0)
         {
            double col[1];
            if(CopyBuffer(handleNonLag_HTF, 1, htfIndex, 1, col)==1)
            {
               int c = (int)col[0];           // 0 gris, 1 rosa, 2 verde
               hud_nlHtfOK = ( (hudSigBuy && c==2) || (hudSigSell && c==1) );
            }
         }
      }
      
      // ---------------- Dibuja HUD ----------------
      //if(DBG_ShowHUD)
      //{
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