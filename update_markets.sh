#!/bin/bash
# ============================================
# Polymarket Radar - 自动更新 markets.json
# 用法: 放到服务器上，cron 每 5 分钟跑一次
# ============================================

# ⬇️ 改成你的网站根目录
WEB_DIR="/var/www/html"
# WEB_DIR="/home/user/public_html"

API_URL="https://gamma-api.polymarket.com/markets?active=true&closed=false&limit=100&order=volume24hr&ascending=false"
OUTPUT="$WEB_DIR/markets.json"
TMP_FILE="/tmp/markets_tmp_$$.json"

echo "[$(date)] 开始更新 markets.json ..."

# 拉取 API 数据
HTTP_CODE=$(curl -s -w "%{http_code}" -o "$TMP_FILE" \
  -H "User-Agent: Mozilla/5.0" \
  --connect-timeout 10 \
  --max-time 30 \
  "$API_URL")

# 检查 HTTP 状态码
if [ "$HTTP_CODE" != "200" ]; then
  echo "[$(date)] ❌ API 请求失败，HTTP $HTTP_CODE"
  rm -f "$TMP_FILE"
  exit 1
fi

# 检查文件是否为有效 JSON 且不为空
if ! python3 -c "import json; d=json.load(open('$TMP_FILE')); assert len(d)>0" 2>/dev/null; then
  echo "[$(date)] ❌ 返回数据无效或为空"
  rm -f "$TMP_FILE"
  exit 1
fi

# 用 python 包装成带 lastUpdated 的格式
python3 -c "
import json, sys
from datetime import datetime, timezone

with open('$TMP_FILE') as f:
    raw = json.load(f)

markets = []
for m in raw:
    try:
        prices = json.loads(m.get('outcomePrices', '[]'))
        yp = float(prices[0]) if prices else 0
    except:
        yp = 0
    
    vol = m.get('volume24hr', 0) or 0
    if vol == 0 and yp < 0.01:
        continue
    
    evt = (m.get('events') or [{}])[0]
    
    markets.append({
        'id': m.get('id', ''),
        'question': m.get('question', ''),
        'slug': m.get('slug', ''),
        'eventSlug': evt.get('slug', ''),
        'eventTitle': evt.get('title', ''),
        'endDate': m.get('endDate', ''),
        'createdAt': m.get('createdAt', ''),
        'outcomePrices': m.get('outcomePrices', '[]'),
        'outcomes': m.get('outcomes', '[]'),
        'lastTradePrice': m.get('lastTradePrice', 0) or 0,
        'bestBid': m.get('bestBid', 0) or 0,
        'bestAsk': m.get('bestAsk', 0) or 0,
        'oneHourPriceChange': m.get('oneHourPriceChange', 0) or 0,
        'oneDayPriceChange': m.get('oneDayPriceChange', 0) or 0,
        'oneWeekPriceChange': m.get('oneWeekPriceChange', 0) or 0,
        'volume24hr': vol,
        'volume1wk': m.get('volume1wk', 0) or 0,
        'liquidityNum': m.get('liquidityNum', 0) or 0,
    })

data = {
    'lastUpdated': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'source': 'Gamma API | polymarket.com',
    'marketCount': len(markets),
    'markets': markets
}

with open('$OUTPUT', 'w') as f:
    json.dump(data, f, ensure_ascii=False)

print(f'[{datetime.now()}] ✅ 已更新 {len(markets)} 个市场 -> $OUTPUT')
"

# 清理
rm -f "$TMP_FILE"
