//
// DayHLNG.mqh
// Alexey Ivannikov (alexey.a.ivannikov@gmail.com)
//

#property version "2.2"
#property copyright "2021, Alexey Ivannikov (alexey.a.ivannikov@gmail.com)"
#property description "Расширенная версия советника, реализующего стратегию DayHL"

#include <Trade/Trade.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/AccountInfo.mqh>
#include <Trade/PositionInfo.mqh>

enum ENUM_ORDER_POSITION {
	ORDER_POSITION_SHADOW,
	ORDER_POSITION_BODY,
	ORDER_POSITION_CLOSE
};

sinput uint i_magicNumber = 19700626;								// MagickNumber
input ENUM_ORDER_POSITION i_ordersPosition = ORDER_POSITION_SHADOW;	// Ориентир для установки ордеров
input uint i_ordersOffset = 0;										// Смещение для ордеров
sinput uint i_maxSpread = 30;										// Максимальный размер спреда
sinput uint i_delay = 0;											// Задержка перед выставлением ордеров
input uint i_minBarSize = 0;										// Минимальный размер свечи
input uint i_maxBarSize = 100000;									// Максимальный размер свечи
input double i_riskLimit = 0.01;									// Допустимый риск (коэффициент)
input double i_fixedVolume = 0.01;									// Фиксированный объем
input uint i_takeProfit = 300;										// Фиксированный TP (пипсы)
input uint i_stopLoss = 200;										// Фиксированный SL (пипсы)
sinput bool i_useBreakeven = false;									// Включить перевод в безубыток
input uint i_breakevenTriggerLevel = 100;							// Уровень перевода позиции в безубыток (пипсы)
input uint i_breakevenValue = 10;									// Величина безубытка (пипсы)
sinput bool i_useFixedTrailing = false;								// Включить фиксированный Trailing Stop
input uint i_fixedTrailingTriggerLevel = 110;						// Уровень включения фиксированного Trailing Stop (пипсы)
input uint i_fixedTrailingValue = 100;								// Величина фиксированного Trailing Stop (пипсы)
sinput bool i_usePsarTrailing = false;								// Включить Trailing Stop по PSAR
input ENUM_TIMEFRAMES i_psarTrailingTimeframe = PERIOD_M15;			// Таймфрейм для Trailing Stop по PSAR
input double i_psarTrailingStep = 0.02;								// Шаг изменения цены для Trailing Stop по PSAR
input double i_psarTrailingMaxStep = 0.2;							// Максимальный шаг для Trailing Stop по PSAR
input uint i_maxOpenedPositions = 1;								// Максимальное количество открытых позиций
sinput string i_orderComment = "DayHLNG";							// Комментарий к ордерам

class CDayHLNG {
public:
	CDayHLNG::CDayHLNG() {
		m_highTicket = m_lowTicket = 0;
		m_lastRateTime = 0;
	};

	int OnInit() {
		m_symbol = Symbol();
		if (!m_symbolInfo.Name(m_symbol)) return INIT_FAILED;

		m_trade.SetExpertMagicNumber(i_magicNumber);

		if (!checkInputParams()) return INIT_FAILED;
//		checkAndCopyParams(params);

		m_lowOrderBarTime = m_highOrderBarTime = getLastRateTime();
		if (m_lowOrderBarTime == 0) return INIT_FAILED;

		if (!EventSetTimer(60)) return INIT_FAILED;

		if (i_usePsarTrailing) {
			m_psarHandle = iSAR(m_symbol, i_psarTrailingTimeframe, i_psarTrailingStep, i_psarTrailingMaxStep);
			if (m_psarHandle == INVALID_HANDLE) {
				EventKillTimer();
				return INIT_FAILED;
			}
		} else {
			m_psarHandle = INVALID_HANDLE;
		}

		return INIT_SUCCEEDED;
	}

	void OnDeinit(const int reason) {
		EventKillTimer();
		if (i_usePsarTrailing && m_psarHandle != INVALID_HANDLE) {
			IndicatorRelease(m_psarHandle);
		}
		m_lastRateTime = 0;
	}

	void OnTick() {
		if (!checkOpenedPositions()) return;

		m_symbolInfo.Refresh();
		m_symbolInfo.RefreshRates();

		int positionsTotal = PositionsTotal();
		for (int i = positionsTotal - 1; i >= 0; i--) {
			if (checkPositionMagickNumber(i)) {
				ulong ticket = m_positionInfo.Ticket();
				double tp = m_positionInfo.TakeProfit();
				double sl = m_positionInfo.StopLoss();

				if (i_useBreakeven && checkCanSetBreakeven(ticket, sl)) {
					modifyPosition(ticket, sl, tp);
				}
				if (i_useFixedTrailing && checkCanFixedTrail(ticket, sl)) {
					modifyPosition(ticket, sl, tp);
				}
				if (i_usePsarTrailing) {
					if (checkCanPsarTrail(ticket, sl)) {
						modifyPosition(ticket, sl, tp);
					} else if (checkCanOpenReversePosition(ticket)) {
						openReversePosition(ticket);
					}
				}
			}
		}
	}

	void OnTimer() {
		datetime t = getLastRateTime();

		if ((t == m_lowOrderBarTime && t == m_highOrderBarTime) || !checkAllowTrade(t)) return;

		m_reversePositionOpened = false;

		MqlRates rates[1];
		if (CopyRates(m_symbol, PERIOD_D1, 1, 1, rates) == -1) {
			PrintFormat("ERROR: CopyRates: %d", GetLastError());
			return;
		}

		if (!checkRateLimits(rates[0])) return;

		m_symbolInfo.Refresh();
		m_symbolInfo.RefreshRates();

		if (t > m_highOrderBarTime && openBuyOrder(rates[0])) {
			m_highOrderBarTime = t;
		}

		if (t > m_lowOrderBarTime && openSellOrder(rates[0])) {
			m_lowOrderBarTime = t;
		}
	}

private:
	string m_symbol;
	datetime m_highOrderBarTime;
	datetime m_lowOrderBarTime;
	ulong m_highTicket;
	ulong m_lowTicket;
	int m_psarHandle;
	datetime m_lastRateTime;
	bool m_reversePositionOpened;

	CTrade m_trade;
	CSymbolInfo m_symbolInfo;
	COrderInfo m_orderInfo;
	CPositionInfo m_positionInfo;
	CAccountInfo m_accountInfo;

	bool checkInputParams() {
		if (i_ordersPosition == ORDER_POSITION_CLOSE && (int)i_ordersOffset < m_symbolInfo.StopsLevel()) {
			return false;
		}
		return true;
	}

	datetime getLastRateTime() {
		datetime buf[1];
		if (CopyTime(m_symbol, PERIOD_D1, 0, 1, buf) == 1) {
			m_lastRateTime = buf[0];
		}
		return m_lastRateTime;
	}

	string getOrderComment() {
		return i_orderComment;
	}

	string getReversePositionComment() {
		string result;
		StringConcatenate(result, getOrderComment(), " reverse");
		return result;
	}

	uint getOpenedPositionsNumber() {
		int positionsNumber = 0;
		for (int i = PositionsTotal(); i > 0; i--) {
			int positionIndex = i - 1;
			string symbol = PositionGetSymbol(positionIndex);
			if (symbol != m_symbol) continue;
			long magicNumber = PositionGetInteger(POSITION_MAGIC);
			if (magicNumber == i_magicNumber) positionsNumber++;
		}
		return positionsNumber;
	}

	bool checkAllowTrade(datetime t) {
		return getOpenedPositionsNumber() < i_maxOpenedPositions &&
			m_symbolInfo.Spread() < (int)i_maxSpread &&
			TimeCurrent() - t > i_delay;
	}

	bool checkRateLimits(const MqlRates& rate) {
		uint delta = (int)MathFloor((rate.high - rate.low) / m_symbolInfo.Point());
		if (delta < i_minBarSize) {
			PrintFormat("NOTICE: Bar is less than limit: bar=%d, limit=%d", delta, i_minBarSize);
			return false;
		} else if (delta > i_maxBarSize) {
			PrintFormat("NOTICE: Bar is greater than limit: bar=%d, limit=%d", delta, i_maxBarSize);
			return false;
		}
		return true;
	}

	bool checkOpenedPositions() {
		return m_positionInfo.SelectByMagic(m_symbol, i_magicNumber);
	}

	bool checkPositionMagickNumber(int positionIndex) {
		return m_positionInfo.SelectByIndex(positionIndex) && m_positionInfo.Magic() == i_magicNumber;
	}

	void deleteAllOrders() {
		int ordersTotal = OrdersTotal();
		for (int i = ordersTotal - 1; i >=0; i--) {
			if (m_orderInfo.SelectByIndex(i) && m_orderInfo.Magic() == i_magicNumber) {
				m_trade.OrderDelete(m_orderInfo.Ticket());
			}
		}
		m_highTicket = m_lowTicket = 0;
	}

	double adjustVolume(double volume) {
    	return MathRound(volume / m_symbolInfo.LotsMin()) * m_symbolInfo.LotsMin();
	}

	double calcVolume(double price, double sl, ENUM_ORDER_TYPE orderType) {
		double loss = m_accountInfo.OrderProfitCheck(m_symbol, orderType, 1, price, sl);
//		PrintFormat("DEBUG: calcVolume: price=%f, sl=%f, loss=%f", price, sl, loss);
    	return adjustVolume(m_accountInfo.Balance() * i_riskLimit / MathAbs(loss));
	}

	double getBodyTopPrice(const MqlRates& rate) {
		return rate.close > rate.open ? rate.close : rate.open;
	}

	double getBodyBottomPrice(const MqlRates& rate) {
		return rate.close > rate.open ? rate.open : rate.close;
	}

	double getBuyPrice(const MqlRates& rate) {
		double price = i_ordersPosition == ORDER_POSITION_SHADOW ?
			rate.high :
			i_ordersPosition == ORDER_POSITION_CLOSE ?
				rate.close :
				getBodyTopPrice(rate);
		return price + (i_ordersOffset + m_symbolInfo.Spread()) * m_symbolInfo.Point();
	}

	double getSellPrice(const MqlRates& rate) {
		double price = i_ordersPosition == ORDER_POSITION_SHADOW ?
			rate.low :
			i_ordersPosition == ORDER_POSITION_CLOSE ?
				rate.close :
				getBodyBottomPrice(rate);
		return price - i_ordersOffset * m_symbolInfo.Point();
	}

	bool openBuyOrder(const MqlRates& rate) {
		static bool priceWarningPrinted = false;
		static bool volumeWargingPrinted = false;

		double price = getBuyPrice(rate);
		if (price < m_symbolInfo.Ask()) {
			if (!priceWarningPrinted) {
				PrintFormat("WARNING: price is less than Ask price: %f < %f", price, m_symbolInfo.Ask());
				priceWarningPrinted = true;
			}
			return false;
		}
		priceWarningPrinted = false;

		double tp = getTP(price, ORDER_TYPE_BUY);
		double sl = getSL(price, ORDER_TYPE_BUY);
		double volume = i_fixedVolume > 0 ? i_fixedVolume : calcVolume(price, sl, ORDER_TYPE_BUY);
		if (volume < m_symbolInfo.LotsMin()) {
			if (!volumeWargingPrinted) {
				PrintFormat("WARNING: Buy volume too small: %f", volume);
				volumeWargingPrinted = true;
			}
			return false;
		}
		volumeWargingPrinted = false;

		bool success = m_trade.BuyStop(volume, price, m_symbol, sl, tp, ORDER_TIME_DAY, 0, getOrderComment());
		if (!success || m_trade.ResultRetcode() != TRADE_RETCODE_DONE) {
			return false;
		}
		m_highTicket = m_trade.ResultOrder();
		return true;
	}

	bool openSellOrder(const MqlRates& rate) {
		static bool priceWarningPrinted = false;
		static bool volumeWargingPrinted = false;

		double price = getSellPrice(rate);
		if (price > m_symbolInfo.Bid()) {
			if (!priceWarningPrinted) {
				PrintFormat("WARNING: price is more than Bid price: %f > %f", price, m_symbolInfo.Bid());
				priceWarningPrinted = true;
			}
			return false;
		}
		priceWarningPrinted = false;

		double tp = getTP(price, ORDER_TYPE_SELL);
		double sl = getSL(price, ORDER_TYPE_SELL);
		double volume = i_fixedVolume > 0 ? i_fixedVolume : calcVolume(price, sl, ORDER_TYPE_SELL);
		if (volume < m_symbolInfo.LotsMin()) {
			if (!volumeWargingPrinted) {
				PrintFormat("WARNING: Sell volume too small");
				volumeWargingPrinted = true;
			}
			return true;
		}
		volumeWargingPrinted = false;

		bool success = m_trade.SellStop(volume, price, m_symbol, sl, tp, ORDER_TIME_DAY, 0, getOrderComment());
		if (!success || m_trade.ResultRetcode() != TRADE_RETCODE_DONE) {
			return false;
		}
		m_lowTicket = m_trade.ResultOrder();
		return true;
	}

	bool checkBullBar(const MqlRates& rate) {
		return rate.open < rate.close;
	}

	bool modifyPosition(ulong ticket, double sl, double tp) {
		MqlTradeRequest request;
		MqlTradeResult result;
		ZeroMemory(request);
		ZeroMemory(result);
		request.action = TRADE_ACTION_SLTP;
		request.symbol = m_symbol;
		request.sl = sl;
		request.tp = tp;
		request.position = ticket;
		request.magic = i_magicNumber;
		return OrderSend(request, result);
	}

	int calcPoints(double pricesDelta) {
		return (int)(pricesDelta / m_symbolInfo.Point());
	}

	double calcPriceDelta(int points) {
		return points * m_symbolInfo.Point();
	}

	bool checkCanSetBreakeven(ulong ticket, double& sl) {
		if (i_breakevenTriggerLevel == 0) return false;
		CPositionInfo pi;
		pi.SelectByTicket(ticket);
		ENUM_POSITION_TYPE type = pi.PositionType();
		double openPrice = pi.PriceOpen(),
			   currentPrice = pi.PriceCurrent();
		sl = pi.StopLoss();

		if (type == POSITION_TYPE_BUY && calcPoints(sl - openPrice) < (int)i_breakevenValue && calcPoints(currentPrice - openPrice) >= (int)i_breakevenTriggerLevel) {
			sl = openPrice + calcPriceDelta(i_breakevenValue);
			return true;
		} else if (type == POSITION_TYPE_SELL && calcPoints(openPrice - sl) < (int)i_breakevenValue && calcPoints(openPrice - currentPrice) >= (int)i_breakevenTriggerLevel) {
			sl = openPrice - calcPriceDelta(i_breakevenValue);
			return true;
		}
		return false;
	}

	bool checkCanFixedTrail(ulong ticket, double &sl) {
		if (i_fixedTrailingValue == 0) return false;
		CPositionInfo pi;
		pi.SelectByTicket(ticket);
		ENUM_POSITION_TYPE type = pi.PositionType();
		double openPrice = pi.PriceOpen(),
			   currentPrice = pi.PriceCurrent();
		sl = pi.StopLoss();

		double trailLevelDelta = i_fixedTrailingTriggerLevel * m_symbolInfo.Point();
		double trailDelta = i_fixedTrailingValue * m_symbolInfo.Point();

		if (type == POSITION_TYPE_BUY && currentPrice - trailLevelDelta > openPrice && currentPrice - trailDelta > sl) {
			sl = currentPrice - trailDelta;
			return true;
		} else if (type == POSITION_TYPE_SELL && currentPrice + trailLevelDelta < openPrice && currentPrice + trailDelta < sl) {
			sl = currentPrice + trailDelta;
			return true;
		}
		return false;
	}

	bool checkCanPsarTrail(ulong ticket, double &sl) {
		CPositionInfo pi;
		pi.SelectByTicket(ticket);
		ENUM_POSITION_TYPE type = pi.PositionType();
		double openPrice = pi.PriceOpen(),
			   currentPrice = pi.PriceCurrent();
		sl = pi.StopLoss();

		double buffer[2];
		int n = CopyBuffer(m_psarHandle, 0, 0, 2, buffer);
		if (n == -1) return false;

		if ((type == POSITION_TYPE_BUY && buffer[1] > buffer[0] && buffer[0] > openPrice && buffer[0] < currentPrice && buffer[0] > sl) ||
		    (type == POSITION_TYPE_SELL && buffer[1] < buffer[0] && buffer[0] < openPrice && buffer[0] > currentPrice && buffer[0] < sl)) {
			sl = buffer[0];
			return true;
		}
		return false;
	}

	bool checkCanOpenReversePosition(ulong ticket) {
		if (m_reversePositionOpened) {
//			Print("DEBUG: Позиция уже открывалась в текущих сутках");
			return false;
		}

		CPositionInfo pi;
		pi.SelectByTicket(ticket);
		if (pi.Time() < m_lastRateTime) {
//			Print("DEBUG: Позиция открыта раньше начала текущих суток");
			return false;
		}

		ENUM_POSITION_TYPE type = pi.PositionType();
		double price = pi.PriceOpen(),
			   sl = pi.StopLoss();

		if ((type == POSITION_TYPE_BUY && price < sl) || (type == POSITION_TYPE_SELL && price > sl)) {
//			Print("DEBUG: Позиция в безубытке");
			return false;
		}

		double buffer[2];
		int n = CopyBuffer(m_psarHandle, 0, 0, 2, buffer);
		if (n == -1) return false;

		price = pi.PriceCurrent();

		if ((price < buffer[0] && price < buffer[1]) || (price > buffer[0] && price > buffer[1])) {
			Print("DEBUG: Инверсия параболика не произошла");
			return false;
		}

		return true;
	}

	ENUM_ORDER_TYPE getReverseOrderType(ENUM_POSITION_TYPE type) {
		if (type == POSITION_TYPE_BUY) {
			return ORDER_TYPE_SELL;
		} else if (type == POSITION_TYPE_SELL) {
			return ORDER_TYPE_BUY;
		}
		return -1;
	}

	double getMarketPrice(ENUM_ORDER_TYPE type) {
		if (type == ORDER_TYPE_BUY) {
			return m_symbolInfo.Ask();
		} else if (type == ORDER_TYPE_SELL) {
			return m_symbolInfo.Bid();
		}
		return -1;
	}

	double getTP(double price, ENUM_ORDER_TYPE type) {
		double delta = calcPriceDelta(i_takeProfit);

		if (type == ORDER_TYPE_BUY) {
			return price + delta;
		} else if (type == ORDER_TYPE_SELL) {
			return price - delta;
		}
		return -1;
	}

	double getSL(double price, ENUM_ORDER_TYPE type) {
		double delta = calcPriceDelta(i_stopLoss);

		if (type == ORDER_TYPE_BUY) {
			return price - delta;
		} else if (type == ORDER_TYPE_SELL) {
			return price + delta;
		}
		return -1;
	}

	bool openReversePosition(ulong ticket) {
		CPositionInfo pi;
		pi.SelectByTicket(ticket);

		ENUM_ORDER_TYPE type = getReverseOrderType(pi.PositionType());
		double volume = pi.Volume();
		double price = getMarketPrice(type);
		double tp = getTP(price, type);
		double sl = getSL(price, type);

		if (!m_trade.PositionOpen(m_symbol, type, volume, price, sl, tp, getReversePositionComment()) ||
			m_trade.ResultRetcode() != TRADE_RETCODE_DONE) {
			return false;
		}

		PrintFormat(
			"Reverse position opened: volume=%f, price=%f, sl=%f, tp=%f",
			volume, price, sl, tp
		);

		m_reversePositionOpened = true;

		return true;
	}
};
