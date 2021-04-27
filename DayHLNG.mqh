#include <Trade/Trade.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/AccountInfo.mqh>
#include <Trade/PositionInfo.mqh>
//#include "ExpertParams.mqh"

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
input uint i_fixedTrailTriggerLevel = 0;							// Уровень включения Trailing Stop (пипсы)
input uint i_fixedTrail = 0;										// Фиксированный Trailing Stop (пипсы)
input uint i_breakevenTriggerLevel = 0;								// Уровень перевода позиции в безубыток (пипсы)
input uint i_breakevenValue = 0;									// Величина безубытка (пипсы)
input uint i_maxOpenedPositions = 1;								// Максимальное количество открытых позиций

class CDayHLNG {
public:
	CDayHLNG::CDayHLNG() {
		m_highTicket = m_lowTicket = 0;
	};

	bool Init(const string symbol) {
		m_symbol = symbol;
		if (!m_symbolInfo.Name(m_symbol)) return false;

		m_trade.SetExpertMagicNumber(i_magicNumber);

		if (!checkInputParams()) return false;
//		checkAndCopyParams(params);

		if (!EventSetTimer(60)) return false;

		m_lowOrderBarTime = m_highOrderBarTime = getLastRateTime();
		if (m_lowOrderBarTime == 0) return false;

		return true;
	}

	void Deinit(const int reason) { EventKillTimer(); }

	void OnTick() {
		if (!checkOpenedPositions()) return;

		int positionsTotal = PositionsTotal();
		for (int i = positionsTotal - 1; i >= 0; i--) {
			if (checkPositionMagickNumber(i)) {
				if (i_breakevenTriggerLevel > 0 && checkCanSetBreakeven()) {
					setPositionBreakeven();
				}
				if (i_fixedTrailTriggerLevel > 0 && i_fixedTrail > 0) {
					trailPosition();
				}
			}
		}
	}

	void OnTimer() {
		datetime t = getLastRateTime();

		if ((t == m_lowOrderBarTime && t == m_highOrderBarTime) || !checkAllowTrade(t)) return;

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
		if (CopyTime(m_symbol, PERIOD_D1, 0, 1, buf) == 1) { return buf[0]; }
		return 0;
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

		double tp = price + i_takeProfit * m_symbolInfo.Point();
		double sl = price - i_stopLoss * m_symbolInfo.Point();
		double volume = i_fixedVolume > 0 ? i_fixedVolume : calcVolume(price, sl, ORDER_TYPE_BUY);
		if (volume < m_symbolInfo.LotsMin()) {
			if (!volumeWargingPrinted) {
				PrintFormat("WARNING: Buy volume too small: %f", volume);
				volumeWargingPrinted = true;
			}
			return false;
		}
		volumeWargingPrinted = false;

		bool success = m_trade.BuyStop(volume, price, m_symbol, sl, tp, ORDER_TIME_DAY);
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

		double tp = price - i_takeProfit * m_symbolInfo.Point();
		double sl = price + i_stopLoss * m_symbolInfo.Point();
		double volume = i_fixedVolume > 0 ? i_fixedVolume : calcVolume(price, sl, ORDER_TYPE_SELL);
		if (volume < m_symbolInfo.LotsMin()) {
			if (!volumeWargingPrinted) {
				PrintFormat("WARNING: Sell volume too small");
				volumeWargingPrinted = true;
			}
			return true;
		}
		volumeWargingPrinted = false;

		bool success = m_trade.SellStop(volume, price, m_symbol, sl, tp, ORDER_TIME_DAY);
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

	void trailPosition() {
		ENUM_POSITION_TYPE type = m_positionInfo.PositionType();
		ulong ticket = m_positionInfo.Ticket();
		double openPrice = m_positionInfo.PriceOpen(),
			   currentPrice = m_positionInfo.PriceCurrent(),
			   tp = m_positionInfo.TakeProfit(),
			   sl = m_positionInfo.StopLoss();

		double trailLevelDelta = i_fixedTrailTriggerLevel * m_symbolInfo.Point();
		double trailDelta = i_fixedTrail * m_symbolInfo.Point();

		if (type == POSITION_TYPE_BUY && currentPrice - trailLevelDelta > openPrice && currentPrice - trailDelta > sl) {
//			PrintFormat("DEBUG: trailPosition: ticket=%I64u, openPrice=%f, currentPrice=%f, fixedDelta=%f", ticket, openPrice, currentPrice, trailDelta);
			modifyPosition(ticket, currentPrice - trailDelta, tp);
		} else if (type == POSITION_TYPE_SELL && currentPrice + trailLevelDelta < openPrice && currentPrice + trailDelta < sl) {
//			PrintFormat("DEBUG: trailPosition: ticket=%I64u, openPrice=%f, currentPrice=%f, fixedDelta=%f", ticket, openPrice, currentPrice, trailDelta);
			modifyPosition(ticket, currentPrice + trailDelta, tp);
		}
	}

	int calcPoints(double pricesDelta) {
		return (int)(pricesDelta / m_symbolInfo.Point());
	}

	double calcPriceDelta(int points) {
		return points * m_symbolInfo.Point();
	}

	bool checkCanSetBreakeven() {
		ENUM_POSITION_TYPE type = m_positionInfo.PositionType();
		double openPrice = m_positionInfo.PriceOpen(),
			   currentPrice = m_positionInfo.PriceCurrent(),
			   sl = m_positionInfo.StopLoss();
		return ((type == POSITION_TYPE_BUY &&
				 calcPoints(sl - openPrice) < (int)i_breakevenValue &&
				 calcPoints(currentPrice - openPrice) >= (int)i_breakevenTriggerLevel) ||
				(type == POSITION_TYPE_SELL &&
				 calcPoints(openPrice - sl) < (int)i_breakevenValue &&
				 calcPoints(openPrice - currentPrice) >= (int)i_breakevenTriggerLevel));

	}

	void setPositionBreakeven() {
		ENUM_POSITION_TYPE type = m_positionInfo.PositionType();
		ulong ticket = m_positionInfo.Ticket();
		double openPrice = m_positionInfo.PriceOpen(),
			   currentPrice = m_positionInfo.PriceCurrent(),
			   tp = m_positionInfo.TakeProfit(),
			   sl = m_positionInfo.StopLoss();

		if (type == POSITION_TYPE_BUY) {
//			PrintFormat("DEBUG: trailPosition: ticket=%I64u, openPrice=%f, currentPrice=%f, fixedDelta=%f", ticket, openPrice, currentPrice, trailDelta);
			modifyPosition(ticket, openPrice + calcPriceDelta(i_breakevenValue), tp);
		} else if (type == POSITION_TYPE_SELL) {
//			PrintFormat("DEBUG: trailPosition: ticket=%I64u, openPrice=%f, currentPrice=%f, fixedDelta=%f", ticket, openPrice, currentPrice, trailDelta);
			modifyPosition(ticket, openPrice - calcPriceDelta(i_breakevenValue), tp);
		}
	}
/*
	void calcStartMoment();
	void calcStopMoment();
	void calcStartStopMoments();
	bool checkCanTrade(const MqlRates& rate);
	void startTrade();
	void setOrders(const MqlRates& rate);
	void stopTrade();
	void closeAllPositions();
	void deleteAllOrders();
	void setBreakEvenIfNeed();
	double adjustVolume(double volume);
	double calcVolume(double sellPrice, double buyPrice);
*/
//    void checkOpenedPositions(int positionsCount);
//    void checkClosedPositions(int positionsCount);
};

/*
double getPositionPricesDiff(const CPositionInfo& pi) {
	return pi.PositionType() == POSITION_TYPE_BUY ?
		pi.PriceCurrent() - pi.PriceOpen() :
		pi.PriceOpen() - pi.PriceCurrent();
	// PrintFormat("getPositionPricesDiff: type=%d, priceCurrent=%f, priceOpen=%f, priceDiff=%f",
	//     pi.PositionType(), pi.PriceCurrent(), pi.PriceOpen(), priceDiff);
	// return priceDiff;
}

void CDayHLNG::setBreakEvenIfNeed() {
	m_position.SelectByTicket(m_positionTicket);
	double price = m_position.PriceOpen(),
		   currentPrice = m_position.PriceCurrent(),
		   tp = m_position.TakeProfit(),
		   sl = m_position.StopLoss(),
		   slNew;
	if (m_position.PositionType() == POSITION_TYPE_BUY && sl < price && currentPrice >= price + m_breakeven * m_priceDiff) {
		slNew = price;
	} else if (m_position.PositionType() == POSITION_TYPE_SELL && sl > price && currentPrice <= price - m_breakeven * m_priceDiff) {
		slNew = price;
	} else {
		return;
	}
	if (m_trade.PositionModify(m_positionTicket, slNew, tp)) {
		PrintFormat("Change position SL: %f -> %f, id=%I64u", sl, slNew, m_positionTicket);
	} else {
		PrintFormat("ERROR: Change SL failed: %d", GetLastError());
	}
}

void CDayHLNG::OnTick() {
	if (m_positionTicket == 0) return;
	setBreakEvenIfNeed();
}

void CDayHLNG::OnTimer() {
	datetime now = TimeLocal();
	if (now >= m_startMoment) {
		startTrade();
	} else if (now >= m_stopMoment) {
		stopTrade();
		calcStopMoment();
	}
}

void CDayHLNG::OnTrade() {
	int positionsCount = PositionsTotal();
	if (positionsCount > 0) {
		if (m_positionTicket == 0) {
			if (!m_position.SelectByMagic(Symbol(), i_magicNumber)) return;
			m_positionTicket = m_position.Identifier();
			PrintFormat("Position opened: id=%I64u", m_positionTicket);
		} else {
			if (!m_position.SelectByMagic(Symbol(), i_magicNumber)) {
				PrintFormat("Position closed: id=%I64u", m_positionTicket);
				m_positionTicket = 0;
			} else {
				long positionTicket = m_position.Identifier();
				if (positionTicket == m_positionTicket) return;
				PrintFormat("Position closed: id=%I64u", m_positionTicket);
				m_positionTicket = positionTicket;
				PrintFormat("Position opened: id=%I64u", m_positionTicket);
			}
		}
	} else {
		if (m_positionTicket == 0) return;
		PrintFormat("Position closed: id=%I64u", m_positionTicket);
		m_positionTicket = 0;
	}
}

void CDayHLNG::OnTradeTransaction(const MqlTradeTransaction& transaction, const MqlTradeRequest& request, const MqlTradeResult& result) {
//    checkPositionCountChanged();
}

bool CDayHLNG::checkCanTrade(const MqlRates& rate) {
	if (!m_account.TradeAllowed()) {
		PrintFormat("CDayHLNG::checkCanTrade: Trade not allowed");
		return false;
	}
	if (!m_account.TradeExpert()) {
		PrintFormat("CDayHLNG::checkCanTrade: Expert trade not allowed");
		return false;
	}
	uint barSize = (uint)MathRound((rate.high - rate.low) / m_symbol.Point());
	if (barSize < m_barMinLimit) {
		PrintFormat("Bar size is too small: low=%f, high=%f, size=%u", rate.low, rate.high, barSize);
		return false;
	}
	if (barSize > m_barMaxLimit) {
		PrintFormat("Bar size is too large: low=%f, high=%f, size=%u", rate.low, rate.high, barSize);
		return false;
	}
	return true;
}

double CDayHLNG::adjustVolume(double volume) {
	return MathRound(volume / m_symbol.LotsMin()) * m_symbol.LotsMin();
}

double CDayHLNG::calcVolume(double sellPrice, double buyPrice) {
	double loss = m_account.OrderProfitCheck(m_symbol.Name(), ORDER_TYPE_BUY, 1, sellPrice, buyPrice);
	return this.adjustVolume(m_account.Balance() * i_riskLimit / loss);
}

void CDayHLNG::setOrders(const MqlRates& rate) {
	double stopsLevel = m_symbol.StopsLevel();
	double point = m_symbol.Point();
	double bodyTop = rate.open > rate.close ? rate.open : rate.close;
	double bodyBottom = rate.open < rate.close ? rate.open : rate.close;
	double buyPrice = m_buyPrice = bodyTop + m_offsetPoints * point;
	double minBuyPrice = m_symbol.Ask() + stopsLevel * point;
	if (buyPrice < minBuyPrice) {
		PrintFormat("CDayHLNG::setOrders: buyPrice correction: %f -> %f", buyPrice, minBuyPrice);
		buyPrice = m_buyPrice = minBuyPrice;
	}
	double sellPrice = m_sellPrice = bodyBottom - m_offsetPoints * point;
	double maxSellPrice = m_symbol.Bid() - stopsLevel * point;
	if (sellPrice > maxSellPrice) {
		PrintFormat("CDayHLNG::setOrders: sellPrice correction: %f -> %f", sellPrice, maxSellPrice);
		sellPrice = m_sellPrice = maxSellPrice;
	}
	double volume = i_fixedVolume > 0 ? i_fixedVolume : this.calcVolume(sellPrice, buyPrice);
	if (volume < m_symbol.LotsMin()) {
		PrintFormat("CDayHLNG::setOrders: volume is less than minimal: volume=%f, minimal=%f", volume, m_symbol.LotsMin());
		return;
	}
	double delta = m_priceDiff = m_buyPrice - m_sellPrice;
	double buyTP = buyPrice + delta * m_profitToRiskRatio,
		   sellTP = sellPrice - delta * m_profitToRiskRatio;
	m_trade.BuyStop(volume, buyPrice, m_symbol.Name(), sellPrice, buyTP, ORDER_TIME_SPECIFIED, m_stopMoment);
	m_trade.SellStop(volume, sellPrice, m_symbol.Name(), buyPrice, sellTP, ORDER_TIME_SPECIFIED, m_stopMoment);
	PrintFormat("CDayHLNG::setOrders: high=%f buy=%f low=%f sell=%f delta=%f", rate.high, buyPrice, rate.low, sellPrice, delta);
}

void CDayHLNG::startTrade() {
	m_symbol.Refresh();
	m_symbol.RefreshRates();
	MqlRates rates[2];
	int n = CopyRates(m_symbol.Name(), PERIOD_H4, 0, 2, rates);
	if (n != -1 && rates[1].time >= m_startMoment) {
		if (checkCanTrade(rates[0])) {
			setOrders(rates[0]);
			calcStartMoment();
		} else {
			calcStartStopMoments();
		}
	}
}

void CDayHLNG::deleteAllOrders() {
	int ordersCount = OrdersTotal();
	COrderInfo oi;
	for (int i = ordersCount - 1; i >=0; i--) {
		if (oi.SelectByIndex(i) && oi.Magic() == i_magicNumber) {
			m_trade.OrderDelete(oi.Ticket());
		}
	}
}

void CDayHLNG::stopTrade() {
	if (m_positionTicket) m_trade.PositionClose(m_positionTicket);
	deleteAllOrders();
}

void CDayHLNG::calcStartMoment() {
	MqlDateTime dt;
	datetime now = TimeLocal(dt);
	if (dt.day_of_week == 0) {
		m_startMoment = now + 3600 * (4 + 23 - dt.hour) + 60 * (59 - dt.min) + (60 - dt.sec);
	} else if (dt.day_of_week == 1 && dt.hour < 4) {
		m_startMoment = now + 3600 * (3 - dt.hour) + 60 * (59 - dt.min) + (60 - dt.sec);
	} else {
		m_startMoment = now + 3600 * (24 * (7 - dt.day_of_week) + 4 + 23 - dt.hour) + 60 * (59 - dt.min) + (60 - dt.sec);
	}
	PrintFormat("now=%I64u, nextStartMoment=%I64u", now, m_startMoment);
}

void CDayHLNG::calcStopMoment() {
	m_stopMoment = m_startMoment + 414000;
}

void CDayHLNG::calcStartStopMoments() {
	calcStartMoment();
	calcStopMoment();
}

*/
