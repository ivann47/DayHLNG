#ifndef _POSITION_MQH_INCLUDED
#define _POSITION_MQH_INCLUDED 1

class Position {
public:
    CPosition() { m_ticket = 0; m_symbol = ""; }

    bool selectByTicket(ulong ticket) {
        if (!PositionSelectByTicket(ticket)) return false;
        if (!getSymbol()) return false;
        m_ticket = ticket;
        return true;
    }

    bool selectByIndex(int index) {
        ulong ticket = PositionGetTicket(index);
        if (ticket == 0) return false;
        if (!getSymbol()) return false;
        m_ticket = ticket;
        return true;
    }

    long getMagic() {
        if (!checkExists()) return 0;
        return PositionGetInteger(POSITION_MAGIC);
    }

    ENUM_POSITION_TYPE getType() {
        if (!checkExists()) return 0;
        return (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    }

    double getVolume() {
        if (!checkExists()) return 0;
        return PositionGetDouble(POSITION_VOLUME);
    }

    double getPriceOpen() {
        if (!checkExists()) return 0;
        return PositionGetDouble(POSITION_PRICE_OPEN);
    }

    double getPriceCurrent() {
        if (!checkExists()) return 0;
        return PositionGetDouble(POSITION_PRICE_CURRENT);
    }

    double getSL() {
        if (!checkExists()) return 0;
        return PositionGetDouble(POSITION_SL);
    }

    double getTP() {
        if (!checkExists()) return 0;
        return PositionGetDouble(POSITION_TP);
    }

    double getSwap() {
        if (!checkExists()) return 0;
        return PositionGetDouble(POSITION_SWAP);
    }

    double getProfit() {
        if (!checkExists()) return 0;
        return PositionGetDouble(POSITION_PROFIT);
    }

    bool modify(sl, tp) {
        if (!checkExists()) return false;
        MqlTradeRequest request;
		MqlTradeResult result;
		ZeroMemory(request);
		ZeroMemory(result);
		request.action = TRADE_ACTION_SLTP;
		request.symbol = m_symbol;
		request.sl = sl;
		request.tp = tp;
		request.position = ticket;
		return OrderSend(request, result);
    }

    bool close() {
        if (!checkExists()) return false;
        MqlTradeRequest request;
		MqlTradeResult result;
		ZeroMemory(request);
		ZeroMemory(result);
		request.action = TRADE_ACTION_SLTP;
		request.symbol = m_symbol;
		request.sl = sl;
		request.tp = tp;
		request.position = ticket;
    }

private:
    ulong m_ticket;
    string m_symbol;

    bool checkExists() {
        return m_ticket != 0 && PositionSelectByTicket(m_ticket);
    }

    bool getSymbol() {
        return PositionGetString(POSITION_SYMBOL, m_symbol);
    }
};

#endif // _POSITION_MQH_INCLUDED
