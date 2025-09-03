// SignalIndicator_main_nlmtf.mq5
//
// Indicador de señales basado en el color del indicador custom
// "NonLag MA mtf". Este indicador dibuja flechas de compra cuando
// el buffer de colores de "NonLag MA mtf" cambia a 2 (color verde)
// y flechas de venta cuando cambia a 1 (color rosa). Se puede
// ajustar el marco de tiempo y parámetros del NonLag MA a través de
// inputs. En futuras versiones se pueden añadir filtros adicionales.

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
#property indicator_width2  1

// Configuración de plot de flechas de venta
#property indicator_label3  "Buy_NL_Signal"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrLimeGreen
#property indicator_width3  1

// Parámetros de entrada para el NonLag MA mtf
input ENUM_TIMEFRAMES NL_TimeFrame = PERIOD_CURRENT;    // Time frame del NonLag MA
input double          NL_Period    = 27;                // Periodo del NonLag MA
input ENUM_APPLIED_PRICE NL_Price  = PRICE_WEIGHTED;    // Precio aplicado
input bool            NL_Interpolate = true;            // Interpolación en modo MTF

//--- Buffers
double NonLagBuffer[];   // Línea principal del indicador
double ColorBuffer[];    // Buffer de color del NonLag MA
double DownNLBuffer[];   // Flechas de venta
double UpNLBuffer[];     // Flechas de compra

int handleNonLag = INVALID_HANDLE;

// Inicialización
int OnInit()
{
   // Asignar buffers
   SetIndexBuffer(0, NonLagBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, ColorBuffer, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, DownNLBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, UpNLBuffer, INDICATOR_DATA);

   // Configurar flechas (códigos Wingdings: 233 arriba, 234 abajo)
   PlotIndexSetInteger(1, PLOT_ARROW, 234); // Venta: flecha abajo
   PlotIndexSetInteger(2, PLOT_ARROW, 233); // Compra: flecha arriba

   // Crear handle del indicador NonLag MA mtf
   // Pasamos los parámetros según el orden esperado por el indicador:
   // 0 (frame code por defecto), periodo, precio, y opcionalmente
   // parámetro de interpolación.
   // Usamos NL_TimeFrame como timeframe de llamada en iCustom para
   // permitir ejecución en otros marcos de tiempo.
   handleNonLag = iCustom(_Symbol, NL_TimeFrame, "NonLag_MA_mtf_smooth", NL_Period, NL_Price, NL_Interpolate);
   if(handleNonLag == INVALID_HANDLE)
   {
      Print("No se pudo crear el handle del NonLag MA mtf");
      return INIT_FAILED;
   }
   
   Print(">>> Indicador de señales cargado con NonLag_MA_mtf_smooth");
   
   return INIT_SUCCEEDED;
}

// Liberación
void OnDeinit(const int reason)
{
   if(handleNonLag != INVALID_HANDLE)
      IndicatorRelease(handleNonLag);
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
   if(rates_total < 2)
      return 0;

   // Copiar buffers desde el NonLag MA mtf
   if(CopyBuffer(handleNonLag, 0, 0, rates_total, NonLagBuffer) <= 0 ||
      CopyBuffer(handleNonLag, 1, 0, rates_total, ColorBuffer) <= 0)
      return 0;
   
   // Iteramos desde prev_calculated - 1 para evitar recalcular todo
   int start = (prev_calculated > 1) ? prev_calculated - 1 : 1;
   // Nos aseguramos de no salirnos del índice al comparar con i+1
   //int lastIndex = rates_total - 2;
   //if(lastIndex < 0)
   //   return rates_total;
   
   for(int i = start; i < rates_total; i++)
   {
      UpNLBuffer[i]   = EMPTY_VALUE;
      DownNLBuffer[i] = EMPTY_VALUE;

      int currentColor = (int)ColorBuffer[i];
      int prevColor    = (int)ColorBuffer[i - 1];

      if(currentColor == 2 && prevColor != 2)
         UpNLBuffer[i] = low[i] - 2 * _Point;
         //UpNLBuffer[i] = high[i] * _Point;
         
      else if(currentColor == 1 && prevColor != 1)
         DownNLBuffer[i] = high[i] + 2 * _Point;
         //DownNLBuffer[i] = low[i] * _Point;
   }
   
   return rates_total;
}