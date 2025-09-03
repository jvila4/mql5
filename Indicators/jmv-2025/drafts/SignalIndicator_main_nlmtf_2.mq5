//+------------------------------------------------------------------+
//|                                 SignalIndicator_main_nlmtf_2.mq5 |
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

input bool UseSlopeFilter = false;        // Activar filtro de slope
input int SlopePeriod = 20;              // Número de pendientes recientes para calcular percentil
input double MinSlopePercentile = 40.0;     // bajado de 70 a 40
input double SlopeTolerance = 0.8;          // tolerancia para pendiente

input bool UseStochasticFilter = false;  // Activar filtro estocástico
input int KPeriod = 5;
input int DPeriod = 3;
input int Slowing = 3;

//--- Buffers
double NonLagBuffer[];   // Línea principal del indicador
double ColorBuffer[];    // Buffer de color del NonLag MA
double DownNLBuffer[];   // Flechas de venta
double UpNLBuffer[];     // Flechas de compra


double kBuffer[], dBuffer[];

int handleNonLag = INVALID_HANDLE;
int handleStoch = INVALID_HANDLE;

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

   return INIT_SUCCEEDED;
}

// Liberación
void OnDeinit(const int reason)
{
   if(handleNonLag != INVALID_HANDLE)
      IndicatorRelease(handleNonLag);
   
   if(handleStoch != INVALID_HANDLE)
      IndicatorRelease(handleStoch);
}

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
   if (rates_total < SlopePeriod + 2)
      return prev_calculated;

   // Copiar buffers desde el NonLag MA mtf
   int nlCount = CopyBuffer(handleNonLag, 0, 0, rates_total, NonLagBuffer);
   int colCount = CopyBuffer(handleNonLag, 1, 0, rates_total, ColorBuffer);
   if (nlCount <= 0 || colCount <= 0)
   {
      Print("❌ No se pudieron copiar los buffers desde NonLag_MA_mtf");
      return prev_calculated;
   }
   int maxAvailable = MathMin(nlCount, colCount);
   int signalsTotal = 0;
   int signalsAccepted = 0;
         
   if(UseStochasticFilter)
   {
      if(CopyBuffer(handleStoch, 0, 0, rates_total, kBuffer) <= 0 ||
         CopyBuffer(handleStoch, 1, 0, rates_total, dBuffer) <= 0)
         {
            Print("❌ No se pudieron copiar los buffers desde handleStoch");
            return prev_calculated;
            //return 0;
         }
   }
   
   // Iteramos desde prev_calculated - 1 para evitar recalcular todo
   //int minBarsRequired = MathMax(SlopePeriod + 1, 20);
   //int start = (prev_calculated > minBarsRequired) ? prev_calculated - 1 : minBarsRequired;
   int start = (prev_calculated > 1) ? prev_calculated - 1 : 1;
   int last = rates_total - 1;

   double recentSlopes[];
   ArrayResize(recentSlopes, SlopePeriod);
   
   //for(int i = start; i < rates_total; i++)   
   for(int i = start; i < MathMin(last, maxAvailable); i++)
   {
      if(ColorBuffer[i] == EMPTY_VALUE || ColorBuffer[i - 1] == EMPTY_VALUE)
         continue;
      
      UpNLBuffer[i]   = EMPTY_VALUE;
      DownNLBuffer[i] = EMPTY_VALUE;
      //NonLagBuffer[i] = EMPTY_VALUE;
      //ColorBuffer[i]  = EMPTY_VALUE;
      
      int currentColor = (int)ColorBuffer[i];
      int prevColor    = (int)ColorBuffer[i - 1];
      
      bool slopeOK = true;
      bool stochOK = true;
      
      if (UseSlopeFilter && i >= SlopePeriod)
      {
         // Calcular pendiente reciente
         //double slope = NonLagBuffer[i] - NonLagBuffer[i - 1];
         double slopePips = (NonLagBuffer[i] - NonLagBuffer[i - 1]) / _Point;

         //Print("SignalIndicator_main_nmmtf-> slope = ", slope);
         Print("SignalIndicator_main_nmmtf-> slopePips = ", slopePips);

         // Desplazar y actualizar buffer de pendientes
         for (int j = 0; j < SlopePeriod - 1; j++)
            recentSlopes[j] = recentSlopes[j + 1];
         //recentSlopes[SlopePeriod - 1] = MathAbs(slope);  // usamos valor absoluto para amplitud
         recentSlopes[SlopePeriod - 1] = MathAbs(slopePips);
      
         // Copia para ordenar
         double sortedSlopes[];
         ArrayCopy(sortedSlopes, recentSlopes);
         ArraySort(sortedSlopes);
   
         // Calcular valor del percentil
         int percentileIndex = (int)MathFloor((MinSlopePercentile / 100.0) * (SlopePeriod - 1));
         double slopeThreshold = sortedSlopes[percentileIndex];

         Print("SignalIndicator_main_nmmtf-> slopeThreshold = ", slopeThreshold);

         
         //slopeOK =  (MathAbs(slope) >= slopeThreshold);
         slopeOK = (MathAbs(slopePips) >= slopeThreshold * SlopeTolerance);
      }

      if(UseStochasticFilter)
      {
         double k = kBuffer[i];
         double d = dBuffer[i];

         // Puedes personalizar la condición según tu criterio (ej: cruce ascendente o zona de sobreventa)
         stochOK = (k > d && k < 30) || (k < d && k > 70);  // ejemplo simple
      }
      
      bool isBuy  = (currentColor == 2 && prevColor != 2 && close[i] > open[i]);
      bool isSell = (currentColor == 1 && prevColor != 1 && close[i] < open[i]);
      //bool isBuy  = (currentColor == 2 && prevColor != 2 && close[i] > open[i] && close[i - 1] > open[i - 1]);
      //bool isSell = (currentColor == 1 && prevColor != 1 && close[i] < open[i] && close[i - 1] < open[i - 1]);     
      
                
      if (isBuy || isSell)
         signalsTotal++;

      if(isBuy && slopeOK && stochOK)
      {
         UpNLBuffer[i] = close[i] + Arrows_Offset * _Point;
         signalsAccepted++;
      }
      else if(isSell && slopeOK && stochOK)
      {
         DownNLBuffer[i] = close[i] - Arrows_Offset * _Point;      
         signalsAccepted++;
      }
   }
   
   Print("Señales totales: ", signalsTotal, ", aceptadas tras filtro: ", signalsAccepted);
   
   return rates_total;
}