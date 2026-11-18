-- ============================================================================
-- FILE: 20260301001000_executive_metrics_rpc.sql
-- TUJUAN: Mengagregasi metrik dashboard di PostgreSQL.
--
-- Sebelumnya dashboard mengambil seluruh baris dari 9 tabel lalu melakukan
-- count/sum di Node.js. RPC ini hanya mengirim satu JSON kecil ke aplikasi dan
-- tetap memakai RLS karena berjalan sebagai SECURITY INVOKER.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_get_executive_metrics()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
    SELECT jsonb_build_object(
        'leads', jsonb_build_object(
            'totalActiveLeads', lead_metrics.total_active_leads,
            'hotLeadsCount', lead_metrics.hot_leads_count,
            'warmLeadsCount', lead_metrics.warm_leads_count,
            'coldLeadsCount', lead_metrics.cold_leads_count
        ),
        'salesAndContracts', jsonb_build_object(
            'salesClosingsCount', deal_metrics.sales_closings_count,
            'totalContractedSalesValue', deal_metrics.total_contracted_sales_value,
            'activeUnderContractCount', deal_metrics.active_under_contract_count
        ),
        'finance', jsonb_build_object(
            'grossVerifiedCashInflow', finance_metrics.gross_verified_cash_inflow,
            'totalRefundedOutflow', finance_metrics.total_refunded_outflow,
            'netVerifiedCashInflow',
                finance_metrics.gross_verified_cash_inflow
                - finance_metrics.total_refunded_outflow,
            'totalForfeitedRetainedFunds', finance_metrics.total_forfeited_retained_funds,
            'outstandingReceivablesTotal', finance_metrics.outstanding_receivables_total,
            'overdueReceivablesAmount', finance_metrics.overdue_receivables_amount,
            'pendingVerificationCount', finance_metrics.pending_verification_count
        ),
        'unitInventory', jsonb_build_object(
            'availableUnitsCount', unit_metrics.available_units_count,
            'heldUnitsCount', unit_metrics.held_units_count,
            'unitsUnderContractOrBookedCount', unit_metrics.booked_units_count,
            'unitsFullySoldCount', unit_metrics.sold_units_count
        ),
        'kprDisbursementSummary', jsonb_build_object(
            'totalApprovedLoanPlafond', kpr_metrics.total_approved_loan_plafond,
            'totalPrimaryDisbursed', kpr_metrics.total_primary_disbursed,
            'totalSubsequentDisbursed', kpr_metrics.total_subsequent_disbursed,
            'totalRemainingUndisbursed', kpr_metrics.total_remaining_undisbursed
        )
    )
    FROM (
        SELECT
            COUNT(*) FILTER (
                WHERE l.pipeline_stage NOT IN ('CLOSED_WON', 'CLOSED_LOST')
            ) AS total_active_leads,
            COUNT(*) FILTER (
                WHERE l.pipeline_stage NOT IN ('CLOSED_WON', 'CLOSED_LOST')
                  AND l.lead_temperature = 'HOT'
            ) AS hot_leads_count,
            COUNT(*) FILTER (
                WHERE l.pipeline_stage NOT IN ('CLOSED_WON', 'CLOSED_LOST')
                  AND l.lead_temperature = 'WARM'
            ) AS warm_leads_count,
            COUNT(*) FILTER (
                WHERE l.pipeline_stage NOT IN ('CLOSED_WON', 'CLOSED_LOST')
                  AND l.lead_temperature = 'COLD'
            ) AS cold_leads_count
        FROM public.leads AS l
    ) AS lead_metrics
    CROSS JOIN (
        SELECT
            COUNT(*) FILTER (
                WHERE d.sales_outcome_status = 'CLOSED_WON'
            ) AS sales_closings_count,
            COALESCE(
                SUM(d.final_deal_value) FILTER (
                    WHERE d.sales_outcome_status = 'CLOSED_WON'
                ),
                0
            ) AS total_contracted_sales_value,
            COUNT(*) FILTER (
                WHERE d.contract_status = 'UNDER_CONTRACT'
            ) AS active_under_contract_count
        FROM public.deals AS d
    ) AS deal_metrics
    CROSS JOIN (
        SELECT
            COALESCE(
                SUM(pr.paid_amount) FILTER (
                    WHERE pr.verification_status = 'VERIFIED'
                ),
                0
            ) AS gross_verified_cash_inflow,
            COUNT(*) FILTER (
                WHERE pr.verification_status = 'PENDING_VERIFICATION'
            ) AS pending_verification_count,
            COALESCE((
                SELECT SUM(rt.refund_amount)
                FROM public.refund_transactions AS rt
                WHERE rt.status = 'COMPLETED'
            ), 0) AS total_refunded_outflow,
            COALESCE((
                SELECT SUM(b.forfeited_retained_amount)
                FROM public.bookings AS b
                WHERE b.status = 'CANCELLED'
            ), 0) AS total_forfeited_retained_funds,
            COALESCE((
                SELECT SUM(ps.remaining_amount)
                FROM public.payment_schedules AS ps
                WHERE ps.status IN ('UNPAID', 'PARTIALLY_PAID', 'OVERDUE')
            ), 0) AS outstanding_receivables_total,
            COALESCE((
                SELECT SUM(ps.remaining_amount)
                FROM public.payment_schedules AS ps
                WHERE ps.status = 'OVERDUE'
            ), 0) AS overdue_receivables_amount
        FROM public.payment_records AS pr
    ) AS finance_metrics
    CROSS JOIN (
        SELECT
            COUNT(*) FILTER (WHERE u.status = 'AVAILABLE') AS available_units_count,
            COUNT(*) FILTER (WHERE u.status = 'HELD') AS held_units_count,
            COUNT(*) FILTER (WHERE u.status = 'BOOKED') AS booked_units_count,
            COUNT(*) FILTER (WHERE u.status = 'SOLD') AS sold_units_count
        FROM public.units AS u
    ) AS unit_metrics
    CROSS JOIN (
        SELECT
            COALESCE(SUM(k.approved_loan_amount), 0) AS total_approved_loan_plafond,
            COALESCE(SUM(k.primary_disbursed_amount), 0) AS total_primary_disbursed,
            COALESCE(SUM(k.subsequent_disbursed_amount), 0) AS total_subsequent_disbursed,
            COALESCE(SUM(k.remaining_undisbursed_amount), 0) AS total_remaining_undisbursed
        FROM public.kpr_applications AS k
        WHERE k.application_status IN ('APPROVED', 'COMPLETED')
          AND k.approved_loan_amount IS NOT NULL
    ) AS kpr_metrics;
$$;

REVOKE ALL ON FUNCTION public.rpc_get_executive_metrics() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_get_executive_metrics() TO authenticated, service_role;

COMMIT;
