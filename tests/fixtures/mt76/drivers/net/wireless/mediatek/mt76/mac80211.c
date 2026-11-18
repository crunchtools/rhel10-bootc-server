// SPDX-License-Identifier: BSD-3-Clause-Clear
/*
 * Copyright (C) 2016 Felix Fietkau <nbd@nbd.name>
 */

/* mt76_sta_add from CentOS Stream 10 kernel-6.12.0-284.el10, unpatched: the
 * fixture tests/kmod-mt76-apply.sh applies kmod/mt76's patch to. */

static int
mt76_sta_add(struct mt76_phy *phy, struct ieee80211_vif *vif,
	     struct ieee80211_sta *sta)
{
	struct mt76_wcid *wcid = (struct mt76_wcid *)sta->drv_priv;
	struct mt76_dev *dev = phy->dev;
	int ret;
	int i;

	mutex_lock(&dev->mutex);

	ret = dev->drv->sta_add(dev, vif, sta);
	if (ret)
		goto out;

	for (i = 0; i < ARRAY_SIZE(sta->txq); i++) {
		struct mt76_txq *mtxq;

		if (!sta->txq[i])
			continue;

		mtxq = (struct mt76_txq *)sta->txq[i]->drv_priv;
		mtxq->wcid = wcid->idx;
	}

	ewma_signal_init(&wcid->rssi);
	rcu_assign_pointer(dev->wcid[wcid->idx], wcid);
	phy->num_sta++;

	mt76_wcid_init(wcid, phy->band_idx);
out:
	mutex_unlock(&dev->mutex);

	return ret;
}

