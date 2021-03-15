//
// DayHLNG.mq5
// Alexey Ivannikov (alexey.a.ivannikov@gmail.com)
//

#property version "1.5"
#property copyright "2021, Alexey Ivannikov (alexey.a.ivannikov@gmail.com)"
#property description "Расширенная версия советника, реализующего стратегию DayHL."

#include "DayHLNG.mqh"

sinput uint i_magicNumber = 19700626;							// MagickNumber
sinput ENUM_HIGH_ORDER_TYPE i_highOrderType = DAYHL_BUY_STOP;	// Тип ордера по high
sinput ENUM_LOW_ORDER_TYPE i_lowOrderType = DAYHL_SELL_STOP;	// Тип ордера по low
input uint i_highOffset = 0;									// Смещение от high
input uint i_lowOffset = 0;										// Смещение от low
input uint i_minLimit = 1;										// Минимальный размер свечи
input uint i_maxLimit = 100000;									// Максимальный размер свечи
input double i_riskLimit = 0.01;								// Допустимый риск (коэффициент)
input double i_fixedVolume = 0;									// Фиксированный объем
input uint i_fixedTP = 0;										// Фиксированный TP (пипсы)
input uint i_fixedSL = 0;										// Фиксированный SL (пипсы)
input double i_profitToRiskRatio = 1.2;							// Соотношение TP/SL
input uint i_breakevenTriggerLevel = 0;							// Уровень цены перевода SL в безубыток (пипсы)
input uint i_breakevenValue = 0;								// Величина безубытка (пипсы)
input uint i_fixedTrailLevel = 0;								// Уровень включения Trailing Stop (пипсы)
input uint i_fixedTrail = 0;									// Фиксированный Trailing Stop (пипсы)
input uint i_maxOpenedPositions = 1;							// Максимальное количество открытых позиций

CDayHLNG expert;

int OnInit() {
	ExpertParams params;

	params.highOrderType = i_highOrderType;
	params.lowOrderType = i_lowOrderType;
	params.highOffset = i_highOffset;
	params.lowOffset = i_lowOffset;
	params.minLimit = i_minLimit;
	params.maxLimit = i_maxLimit;
	params.riskLimit = i_riskLimit;
	params.fixedVolume = i_fixedVolume;
	params.fixedTP = i_fixedTP;
	params.fixedSL = i_fixedSL;
	params.profitToRiskRatio = i_profitToRiskRatio;
	params.breakevenTriggerLevel = i_breakevenTriggerLevel;
	params.breakevenValue = i_breakevenValue;
	params.fixedTrailLevel = i_fixedTrailLevel;
	params.fixedTrail = i_fixedTrail;
	params.maxOpenedPositions = i_maxOpenedPositions;

	if (!expert.Init(Symbol(), i_magicNumber, params)) {
		return(INIT_FAILED);
	}

	return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
	expert.Deinit(reason);
}

void OnTick() {
	expert.OnTick();
}

void OnTimer() {
	expert.OnTimer();
}

void OnTrade() {
	expert.OnTrade();
}

void OnTradeTransaction(const MqlTradeTransaction& transaction, const MqlTradeRequest& request, const MqlTradeResult& result) {
	expert.OnTradeTransaction(transaction, request, result);
}
