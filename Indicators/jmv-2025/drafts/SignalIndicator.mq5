// SignalIndicator.mq5
//
// Indicador personalizado que visualiza señales de compra y venta
// basadas en el cruce de medias móviles (EMA 5 y EMA 10) y filtros
// de RSI y Estocástico. Cuando se cumplen las condiciones de compra,
// se dibuja una flecha verde bajo la vela correspondiente; para
// condiciones de venta, se dibuja una flecha roja sobre la vela.
// El indicador se calcula para cada barra y puede servir como
// referencia visual para el robot intradía.

#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

// Configuración de primer plot (flechas de compra)
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  1
#property indicator_label1  "BuySignal"

// Configuración de segundo plot (flechas de venta)
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  1
#property indicator_label2  "SellSignal"

double UpSignalBuffer[];
double DownSignalBuffer[];

int handleEMA5;
int handleEMA10;
int handleRSI;
int handleStoch;

// Inicialización del indicador
int OnInit()
{
   // Asignar buffers
   SetIndexBuffer(0, UpSignalBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, DownSignalBuffer, INDICATOR_DATA);

   // Configurar código de flecha (Wingdings 233: flecha hacia arriba)
   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   // Código 234: flecha hacia abajo
   PlotIndexSetInteger(1, PLOT_ARROW, 234);

   // Crear handles para indicadores internos
   handleEMA5  = iMA(_Symbol, _Period, 5, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA10 = iMA(_Symbol, _Period, 10, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI   = iRSI(_Symbol, _Period, 14, PRICE_CLOSE);
   // Para obtener %K del Estocástico
   // Para el estocástico usamos el cálculo por defecto (low/high)
   handleStoch = iStochastic(_Symbol, _Period, 14, 3, 3, MODE_SMA, STO_LOWHIGH);

   if(handleEMA5 == INVALID_HANDLE || handleEMA10 == INVALID_HANDLE ||
      handleRSI == INVALID_HANDLE || handleStoch == INVALID_HANDLE)
   {
      Print("Error creando manejadores de indicadores");
      return(INIT_FAILED);
   }
   return(INIT_SUCCEEDED);
}

// Desinicialización
void OnDeinit(const int reason)
{
   if(handleEMA5 != INVALID_HANDLE)   IndicatorRelease(handleEMA5);
   if(handleEMA10 != INVALID_HANDLE)  IndicatorRelease(handleEMA10);
   if(handleRSI != INVALID_HANDLE)    IndicatorRelease(handleRSI);
   if(handleStoch != INVALID_HANDLE)  IndicatorRelease(handleStoch);
}

// Cálculo del indicador
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
   // Necesitamos al menos tantas barras como el periodo más grande
   if(rates_total < 50)
      return 0;

   // Arrays para indicadores
   static double ema5Array[];
   static double ema10Array[];
   static double rsiArray[];
   static double stochKArray[];

   int toCopy = rates_total;
   // Copiar buffers completos
   if(CopyBuffer(handleEMA5, 0, 0, toCopy, ema5Array) <= 0) return 0;
   if(CopyBuffer(handleEMA10, 0, 0, toCopy, ema10Array) <= 0) return 0;
   if(CopyBuffer(handleRSI, 0, 0, toCopy, rsiArray) <= 0) return 0;
   // Stochastic: la serie %K está en buffer 0
   if(CopyBuffer(handleStoch, 0, 0, toCopy, stochKArray) <= 0) return 0;

   // Recorrer desde la barra prev_calculated-1 (o desde 0 la primera vez)
   int start = (prev_calculated > 0) ? prev_calculated - 1 : 0;
   // Nos aseguramos de no acceder fuera del rango al comparar con la barra siguiente (i+1)
   int lastIndex = rates_total - 2;
   if(lastIndex < 0) return rates_total;
   for(int i=start; i<=lastIndex; i++)
   {
      UpSignalBuffer[i]   = EMPTY_VALUE;
      DownSignalBuffer[i] = EMPTY_VALUE;

      // Definir condición actual de compra y venta
      bool buyNow  = (ema5Array[i] > ema10Array[i] && rsiArray[i] > 50.0 && stochKArray[i] > 50.0);
      bool buyPrev = (ema5Array[i+1] > ema10Array[i+1] && rsiArray[i+1] > 50.0 && stochKArray[i+1] > 50.0);
      bool sellNow  = (ema5Array[i] < ema10Array[i] && rsiArray[i] < 50.0 && stochKArray[i] < 50.0);
      bool sellPrev = (ema5Array[i+1] < ema10Array[i+1] && rsiArray[i+1] < 50.0 && stochKArray[i+1] < 50.0);

      // Generar señal solo en la inflexión: cuando aparece la condición y no estaba en la barra anterior
      if(buyNow && !buyPrev)
      {
         UpSignalBuffer[i] = low[i] - 2*_Point;
      }
      else if(sellNow && !sellPrev)
      {
         DownSignalBuffer[i] = high[i] + 2*_Point;
      }
   }
   return rates_total;
}