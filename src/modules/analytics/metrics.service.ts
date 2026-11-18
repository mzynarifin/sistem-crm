// Lokasi: src/modules/analytics/metrics.service.ts
// Level Topologis: L11 (Layanan Agregasi Akhir untuk Modul S [Dashboard] & Modul T [Reporting])

import 'server-only';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { translateDatabaseOrRpcError } from '@/lib/errors/app-error';

export interface StandardizedExecutiveMetrics {
  // 1. Metrik Lead & Temperatur
  leads: {
    totalActiveLeads: number;
    hotLeadsCount: number;
    warmLeadsCount: number;
    coldLeadsCount: number;
  };
  // 2. Metrik Penjualan & Kontrak (Dipisahkan tegas sesuai Kamus Metrik Bagian 3.1)
  salesAndContracts: {
    salesClosingsCount: number; // Jumlah Deal dengan sales_outcome_status = 'CLOSED_WON'
    totalContractedSalesValue: number; // Sum(final_deal_value) dari Deal 'CLOSED_WON'
    activeUnderContractCount: number; // Deal dengan contract_status = 'UNDER_CONTRACT'
  };
  // 3. Metrik Realisasi Kas, Refund & Piutang
  finance: {
    grossVerifiedCashInflow: number; // Sum(paid_amount) dari payment_records 'VERIFIED'
    totalRefundedOutflow: number; // Sum(refund_amount) dari refund_transactions 'COMPLETED'
    netVerifiedCashInflow: number; // Gross Verified - Total Refunded
    totalForfeitedRetainedFunds: number; // Sum(forfeited_retained_amount) dari bookings 'CANCELLED'
    outstandingReceivablesTotal: number; // Sum(remaining_amount) dari jadwal aktif belum 'PAID'
    overdueReceivablesAmount: number; // Sum(remaining_amount) dari jadwal berstatus 'OVERDUE'
    pendingVerificationCount: number; // Antrean bukti bayar 'PENDING_VERIFICATION'
  };
  // 4. Metrik Status Inventaris Unit (Ketetapan Final TC-01A: SOLD hanya saat lunas / 100% FULLY_DISBURSED)
  unitInventory: {
    availableUnitsCount: number; // status = 'AVAILABLE'
    heldUnitsCount: number; // status = 'HELD' (Ditahan sementara 72 jam)
    unitsUnderContractOrBookedCount: number; // status = 'BOOKED' (Termasuk Cash Bertahap Under Contract & KPR belum cair 100%)
    unitsFullySoldCount: number; // status = 'SOLD' (Lunas 100% / KPR FULLY_DISBURSED)
  };
  // 5. Metrik Pencairan KPR (Hanya pengajuan berstatus APPROVED / COMPLETED)
  kprDisbursementSummary: {
    totalApprovedLoanPlafond: number;
    totalPrimaryDisbursed: number;
    totalSubsequentDisbursed: number;
    totalRemainingUndisbursed: number;
  };
}

export const ExecutiveMetricsService = {
  /**
   * Mengambil seluruh metrik standar sesuai cakupan RLS pengguna yang sedang login
   * (Sales = Pribadi, Supervisor = Timnya, Admin = Seluruh Perusahaan).
   * Side effect system sweep dijadwalkan oleh page layer dengan `after()` agar
   * tidak memblokir response metrik.
   */
  async getStandardizedMetrics(): Promise<StandardizedExecutiveMetrics> {
    const supabase = await createSupabaseServerClient();

    const { data, error } = await supabase.rpc('rpc_get_executive_metrics');
    if (error) {
      throw translateDatabaseOrRpcError(error);
    }

    // JSONB number di-normalisasi agar kontrak service tetap konsisten walaupun
    // driver/database mengembalikan nilai NUMERIC sebagai string.
    const raw = data as StandardizedExecutiveMetrics;
    const toNumber = (value: number | string | null | undefined) => Number(value ?? 0);

    return {
      leads: {
        totalActiveLeads: toNumber(raw.leads.totalActiveLeads),
        hotLeadsCount: toNumber(raw.leads.hotLeadsCount),
        warmLeadsCount: toNumber(raw.leads.warmLeadsCount),
        coldLeadsCount: toNumber(raw.leads.coldLeadsCount),
      },
      salesAndContracts: {
        salesClosingsCount: toNumber(raw.salesAndContracts.salesClosingsCount),
        totalContractedSalesValue: toNumber(raw.salesAndContracts.totalContractedSalesValue),
        activeUnderContractCount: toNumber(raw.salesAndContracts.activeUnderContractCount),
      },
      finance: {
        grossVerifiedCashInflow: toNumber(raw.finance.grossVerifiedCashInflow),
        totalRefundedOutflow: toNumber(raw.finance.totalRefundedOutflow),
        netVerifiedCashInflow: toNumber(raw.finance.netVerifiedCashInflow),
        totalForfeitedRetainedFunds: toNumber(raw.finance.totalForfeitedRetainedFunds),
        outstandingReceivablesTotal: toNumber(raw.finance.outstandingReceivablesTotal),
        overdueReceivablesAmount: toNumber(raw.finance.overdueReceivablesAmount),
        pendingVerificationCount: toNumber(raw.finance.pendingVerificationCount),
      },
      unitInventory: {
        availableUnitsCount: toNumber(raw.unitInventory.availableUnitsCount),
        heldUnitsCount: toNumber(raw.unitInventory.heldUnitsCount),
        unitsUnderContractOrBookedCount: toNumber(
          raw.unitInventory.unitsUnderContractOrBookedCount
        ),
        unitsFullySoldCount: toNumber(raw.unitInventory.unitsFullySoldCount),
      },
      kprDisbursementSummary: {
        totalApprovedLoanPlafond: toNumber(
          raw.kprDisbursementSummary.totalApprovedLoanPlafond
        ),
        totalPrimaryDisbursed: toNumber(raw.kprDisbursementSummary.totalPrimaryDisbursed),
        totalSubsequentDisbursed: toNumber(
          raw.kprDisbursementSummary.totalSubsequentDisbursed
        ),
        totalRemainingUndisbursed: toNumber(
          raw.kprDisbursementSummary.totalRemainingUndisbursed
        ),
      },
    };
  },
};
