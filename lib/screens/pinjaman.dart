import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app.dart';
import '../widgets/navbar.dart';

const String _kTabelJenisPinjaman = 'jenis_pinjaman';
const String _kTabelPendapatan = 'pendapatan';
const String _kTabelTabungan = 'tabungan';

const List<IconData> _kJenisIcons = [
  Icons.storefront,
  Icons.domain_add,
  Icons.account_balance_wallet,
  Icons.real_estate_agent,
  Icons.credit_card,
  Icons.savings,
];

const List<Color> _kDonutColors = [
  AppColors.primary,
  AppColors.secondary,
  Color(0xFF485F83),
  Color(0xFFF2632F),
  Color(0xFFB0C8F1),
];

const List<String> _kPeriodeOptions = [
  'Q1 2024',
  'Q2 2024',
  'Q3 2024',
  'Q4 2024',
  'Q1 2025',
  'Q2 2025',
];

class JenisPinjamanEntry {
  final int idJenis;
  final int nomorUrut;
  final String namaJenis;
  final double totalPenyaluran;

  JenisPinjamanEntry({
    required this.idJenis,
    required this.nomorUrut,
    required this.namaJenis,
    required this.totalPenyaluran,
  });

  String get kodeJenis => 'JENIS $nomorUrut';
  IconData get icon => _kJenisIcons[(nomorUrut - 1) % _kJenisIcons.length];
}

class TabunganKantorEntry {
  final String namaKantor;
  final double totalTabungan;

  TabunganKantorEntry({
    required this.namaKantor,
    required this.totalTabungan,
  });
}

class PinjamanScreen extends StatefulWidget {
  const PinjamanScreen({super.key});

  @override
  State<PinjamanScreen> createState() => _PinjamanScreenState();
}

class _PinjamanScreenState extends State<PinjamanScreen> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _errorMessage;
  bool _isExportingJenis = false;
  bool _isExportingTabungan = false;

  List<JenisPinjamanEntry> _allJenis = [];

  bool _tabunganLoading = true;
  String? _tabunganError;
  List<TabunganKantorEntry> _tabunganList = [];

  String _selectedPeriode = 'Q3 2024';

  @override
  void initState() {
    super.initState();
    _loadJenisPinjaman();
    _loadTabungan();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadJenisPinjaman(), _loadTabungan()]);
  }

  // Load daftar jenis pinjaman + total penyaluran per jenis
  Future<void> _loadJenisPinjaman() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final results = await Future.wait([
        _supabase
            .from(_kTabelJenisPinjaman)
            .select('id_jenis, nama_jenis')
            .order('id_jenis', ascending: true),
        _supabase
            .from(_kTabelPendapatan)
            .select('nominal, jenis_pinjaman(id_jenis)'),
      ]);

      final jenisRows = results[0] as List<dynamic>;
      final pendapatanRows = results[1] as List<dynamic>;

      final totalByJenis = <int, double>{};
      for (final raw in pendapatanRows) {
        final row = raw as Map<String, dynamic>;
        final jenis = row['jenis_pinjaman'] as Map<String, dynamic>?;
        final idJenis = (jenis?['id_jenis'] as num?)?.toInt();
        if (idJenis == null) continue;
        final nominal = (row['nominal'] as num?)?.toDouble() ?? 0;
        totalByJenis[idJenis] = (totalByJenis[idJenis] ?? 0) + nominal;
      }

      final jenisList = <JenisPinjamanEntry>[];
      for (var i = 0; i < jenisRows.length; i++) {
        final row = jenisRows[i] as Map<String, dynamic>;
        final idJenis = (row['id_jenis'] as num).toInt();
        jenisList.add(
          JenisPinjamanEntry(
            idJenis: idJenis,
            nomorUrut: i + 1,
            namaJenis: (row['nama_jenis'] as String?) ?? '-',
            totalPenyaluran: totalByJenis[idJenis] ?? 0,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _allJenis = jenisList;
        _isLoading = false;
      });
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Gagal memuat data jenis pinjaman: ${error.message}';
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Gagal memuat data jenis pinjaman: $error';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadTabungan() async {
    setState(() {
      _tabunganLoading = true;
      _tabunganError = null;
    });
    try {
      final rows = await _supabase
          .from(_kTabelTabungan)
          .select('nominal, kantor(nama_kantor)');

      final totalByKantor = <String, double>{};
      for (final raw in rows as List<dynamic>) {
        final row = raw as Map<String, dynamic>;
        final kantor = row['kantor'] as Map<String, dynamic>?;
        final nama = (kantor?['nama_kantor'] as String?) ?? 'Lainnya';
        final nominal = (row['nominal'] as num?)?.toDouble() ?? 0;
        totalByKantor[nama] = (totalByKantor[nama] ?? 0) + nominal;
      }

      final list =
          totalByKantor.entries
              .map(
                (e) => TabunganKantorEntry(
                  namaKantor: e.key,
                  totalTabungan: e.value,
                ),
              )
              .toList()
            ..sort((a, b) => b.totalTabungan.compareTo(a.totalTabungan));

      if (!mounted) return;
      setState(() {
        _tabunganList = list;
        _tabunganLoading = false;
      });
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() {
        _tabunganError = 'Data tabungan belum tersedia (${error.message})';
        _tabunganLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _tabunganError = 'Data tabungan belum tersedia: $error';
        _tabunganLoading = false;
      });
    }
  }

  List<JenisPinjamanEntry> get _filteredJenis => _allJenis;

  double get _totalTabungan =>
      _tabunganList.fold<double>(0, (a, b) => a + b.totalTabungan);

  List<TabunganKantorEntry> get _tabunganSegmen {
    if (_tabunganList.length <= 5) return _tabunganList;
    final top = _tabunganList.take(4).toList();
    final sisa = _tabunganList
        .skip(4)
        .fold<double>(0, (a, b) => a + b.totalTabungan);
    top.add(
      TabunganKantorEntry(namaKantor: 'Kantor Lainnya & Kas', totalTabungan: sisa),
    );
    return top;
  }

  // ---- Helper format ----
  String _formatNumber(double value) => value
      .toStringAsFixed(0)
      .replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (match) => '${match[1]}.',
      );

  String _formatSingkat(double value, {int desimalMiliar = 1}) {
    if (value >= 1000000000) {
      final s = (value / 1000000000)
          .toStringAsFixed(desimalMiliar)
          .replaceAll('.', ',');
      return 'Rp $s M';
    }
    if (value >= 1000000) {
      return 'Rp ${(value / 1000000).round()} Jt';
    }
    return 'Rp ${_formatNumber(value)}';
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? AppColors.error : AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ---- Export ----
  Future<void> _exportJenisXlsx() async {
    if (_allJenis.isEmpty) {
      _showMessage('Belum ada data jenis pinjaman untuk diekspor', error: true);
      return;
    }
    setState(() => _isExportingJenis = true);
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Jenis Pinjaman'];
      sheet.appendRow(
        [
          'Kode',
          'Nama Jenis',
          'Total Penyaluran (Rp)',
        ].map(TextCellValue.new).toList(),
      );
      for (final j in _allJenis) {
        sheet.appendRow([
          TextCellValue(j.kodeJenis),
          TextCellValue(j.namaJenis),
          DoubleCellValue(j.totalPenyaluran),
        ]);
      }
      await _saveAndShare(excel, 'rekap_jenis_pinjaman', 'Rekap Jenis Pinjaman (Excel)');
    } catch (error) {
      _showMessage('Export gagal: $error', error: true);
    } finally {
      if (mounted) setState(() => _isExportingJenis = false);
    }
  }

  Future<void> _exportTabunganXlsx() async {
    if (_tabunganList.isEmpty) {
      _showMessage('Belum ada data tabungan untuk diekspor', error: true);
      return;
    }
    setState(() => _isExportingTabungan = true);
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Distribusi Tabungan'];
      sheet.appendRow(
        ['Kantor', 'Total Tabungan (Rp)'].map(TextCellValue.new).toList(),
      );
      for (final t in _tabunganList) {
        sheet.appendRow([
          TextCellValue(t.namaKantor),
          DoubleCellValue(t.totalTabungan),
        ]);
      }
      await _saveAndShare(excel, 'rekap_tabungan_kantor', 'Rekap Tabungan Kantor (Excel)');
    } catch (error) {
      _showMessage('Export gagal: $error', error: true);
    } finally {
      if (mounted) setState(() => _isExportingTabungan = false);
    }
  }

  Future<void> _saveAndShare(Excel excel, String prefix, String subject) async {
    final bytes = excel.save();
    if (bytes == null) throw StateError('Gagal membuat berkas Excel');
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.xlsx',
    );
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: subject),
    );
  }

  Future<void> _pickPeriode() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainer,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Pilih Periode',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final periode in _kPeriodeOptions)
              ListTile(
                title: Text(periode),
                trailing: periode == _selectedPeriode
                    ? const Icon(Icons.check, color: AppColors.secondary)
                    : null,
                onTap: () => Navigator.of(context).pop(periode),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _selectedPeriode = selected);
    }
  }

  void _openJenisDetail(JenisPinjamanEntry jenis) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _JenisDetailSheet(
        jenis: jenis,
        formatSingkat: _formatSingkat,
      ),
    );
  }

  // ---- UI ----
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: _buildTopBar(),
    bottomNavigationBar: const AppNavBar(currentTab: AppTab.pinjaman),
    body: SafeArea(top: false, child: _buildBody()),
  );

  PreferredSizeWidget _buildTopBar() => PreferredSize(
    preferredSize: const Size.fromHeight(64),
    child: ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          color: AppColors.background.withValues(alpha: 0.85),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 64,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.account_balance,
                        size: 18,
                        color: AppColors.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'FundMonitor',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.primary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _isLoading ? null : _loadAll,
                      icon: const Icon(Icons.notifications_outlined),
                      color: AppColors.onSurfaceVariant,
                      tooltip: 'Muat ulang',
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.surfaceContainerHigh,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person,
                        size: 18,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 40, color: AppColors.error),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadJenisPinjaman,
                icon: const Icon(Icons.refresh),
                label: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filteredJenis;

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _headerRow(),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            _emptyJenisState()
          else
            ...filtered.map(
              (j) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _jenisCard(j),
              ),
            ),
          const SizedBox(height: 4),
          _distribusiTabunganCard(),
          const SizedBox(height: 12),
          _bottomActionButtons(),
        ],
      ),
    );
  }

  Widget _headerRow() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.secondary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'PORTOFOLIO & LIKUIDITAS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              'Jenis Pinjaman',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      Material(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _pickPeriode,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: AppColors.secondary,
                ),
                const SizedBox(width: 6),
                Text(
                  _selectedPeriode,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(width: 6),
      Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _isExportingJenis ? null : _exportJenisXlsx,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: _isExportingJenis
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.download,
                      size: 20,
                      color: AppColors.onPrimary,
                    ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _emptyJenisState() => Container(
    padding: const EdgeInsets.all(24),
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            color: AppColors.surfaceContainer,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.filter_alt_off,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Belum Ada Jenis Pinjaman',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
        ),
        const SizedBox(height: 4),
        const Text(
          'Tidak ada jenis pinjaman yang tercatat.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
        ),
      ],
    ),
  );

  Widget _jenisCard(JenisPinjamanEntry jenis) => Material(
    color: AppColors.surfaceContainerLowest,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openJenisDetail(jenis),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(jenis.icon, size: 22, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          jenis.kodeJenis,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        jenis.namaJenis,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColors.outline,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _miniStat(
                      'Total Penyaluran',
                      _formatSingkat(jenis.totalPenyaluran),
                      AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _miniStat(String label, String value, Color valueColor) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: valueColor,
        ),
      ),
    ],
  );

  Widget _distribusiTabunganCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.pie_chart,
                        size: 20,
                        color: AppColors.secondary,
                      ),
                      const SizedBox(width: 6),
                      const Flexible(
                        child: Text(
                          'Distribusi Tabungan Kantor',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Rasio likuiditas simpanan per unit kantor',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (!_tabunganLoading && _tabunganError == null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF86F2E4),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_tabunganSegmen.length} Kluster',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF006F66),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_tabunganLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_tabunganError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                const Icon(
                  Icons.savings_outlined,
                  size: 32,
                  color: AppColors.onSurfaceVariant,
                ),
                const SizedBox(height: 8),
                Text(
                  _tabunganError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _loadTabungan,
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          )
        else if (_tabunganList.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Belum ada data tabungan.',
                style: TextStyle(color: AppColors.onSurfaceVariant),
              ),
            ),
          )
        else
          _donutSection(),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.verified_user,
                size: 18,
                color: AppColors.secondary,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Perhitungan rasio likuiditas tabungan divalidasi harian',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'Status Sehat',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _donutSection() {
    final segmen = _tabunganSegmen;
    final total = _totalTabungan;
    final persentase = total == 0
        ? <double>[]
        : segmen.map((s) => s.totalTabungan / total).toList();

    return Column(
      children: [
        Center(
          child: SizedBox(
            width: 180,
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(180, 180),
                  painter: _DonutPainter(
                    percentages: persentase,
                    colors: _kDonutColors,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'TOTAL TABUNGAN',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.4,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatSingkat(total, desimalMiliar: 2),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        '100% Tercakup',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Column(
          children: [
            for (var i = 0; i < segmen.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _legendRow(
                  color: _kDonutColors[i % _kDonutColors.length],
                  nama: segmen[i].namaKantor,
                  persen: total == 0 ? 0 : (segmen[i].totalTabungan / total * 100),
                  nominal: segmen[i].totalTabungan,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _legendRow({
    required Color color,
    required String nama,
    required double persen,
    required double nominal,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            nama,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: AppColors.onSurface),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${persen.toStringAsFixed(0)}%',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          _formatSingkat(nominal),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
      ],
    ),
  );

  Widget _bottomActionButtons() => Row(
    children: [
      Expanded(
        child: Material(
          color: AppColors.secondary,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _isExportingTabungan ? null : _exportTabunganXlsx,
            child: Container(
              height: 48,
              alignment: Alignment.center,
              child: _isExportingTabungan
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.table_view, size: 20, color: AppColors.onPrimary),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Unduh Laporan',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: AppColors.onPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Material(
          color: const Color(0xFF0F294A),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _pickPeriode,
            child: Container(
              height: 48,
              alignment: Alignment.center,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune, size: 20, color: AppColors.onPrimary),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Filter Periode',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _DonutPainter extends CustomPainter {
  final List<double> percentages;
  final List<Color> colors;

  _DonutPainter({required this.percentages, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    if (percentages.isEmpty) return;
    final strokeWidth = size.width * 0.16;
    final radius = (size.width - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    var startAngle = -math.pi / 2;
    const gap = 0.02; // celah kecil antar segmen

    for (var i = 0; i < percentages.length; i++) {
      final sweep = (percentages[i] * 2 * math.pi - gap).clamp(
        0.0,
        2 * math.pi,
      );
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        false,
        paint,
      );
      startAngle += percentages[i] * 2 * math.pi;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.percentages != percentages ||
        oldDelegate.colors != colors;
  }
}

class _JenisDetailSheet extends StatelessWidget {
  final JenisPinjamanEntry jenis;
  final String Function(double, {int desimalMiliar}) formatSingkat;

  const _JenisDetailSheet({required this.jenis, required this.formatSingkat});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: ListView(
          controller: scrollController,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(jenis.icon, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          jenis.kodeJenis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        jenis.namaJenis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  _detailStat(
                    'Total Penyaluran',
                    formatSingkat(jenis.totalPenyaluran),
                    AppColors.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Tutup'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailStat(String label, String value, Color valueColor) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          color: valueColor,
        ),
      ),
    ],
  );
}