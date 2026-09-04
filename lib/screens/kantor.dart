import 'dart:io';
import 'dart:ui';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app.dart';
import '../widgets/navbar.dart';

const List<Color> _kKomposisiColors = [
  AppColors.primary,
  AppColors.secondary,
  Color(0xFFE8871E),
  Color(0xFF7C4DFF),
];

class KantorEntry {
  final int idKantor;
  final String namaKantor;
  final String alamat;
  final String wilayah;
  final double totalPenyaluran;
  final int jumlahTransaksi;
  final Map<String, double> komposisiJenis;

  KantorEntry({
    required this.idKantor,
    required this.namaKantor,
    required this.alamat,
    required this.wilayah,
    required this.totalPenyaluran,
    required this.jumlahTransaksi,
    required this.komposisiJenis,
  });

  String get kodeKantor => 'KTR-${idKantor.toString().padLeft(2, '0')}';
  bool get punyaTransaksi => jumlahTransaksi > 0;
}

class KantorScreen extends StatefulWidget {
  const KantorScreen({super.key});

  @override
  State<KantorScreen> createState() => _KantorScreenState();
}

class _KantorScreenState extends State<KantorScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isExporting = false;
  String? _errorMessage;

  List<KantorEntry> _allKantor = [];
  List<String> _wilayahList = [];
  String _selectedWilayah = 'all';
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Load Database
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final results = await Future.wait([
        _supabase
            .from('kantor')
            .select('id_kantor, nama_kantor, alamat, wilayah')
            .order('id_kantor', ascending: true),
        _supabase
            .from('pendapatan')
            .select('id_kantor, nominal, jenis_pinjaman(nama_jenis)'),
      ]);

      final kantorRows = results[0] as List<dynamic>;
      final pendapatanRows = results[1] as List<dynamic>;

      final totalByKantor = <int, double>{};
      final countByKantor = <int, int>{};
      final komposisiByKantor = <int, Map<String, double>>{};

      for (final raw in pendapatanRows) {
        final row = raw as Map<String, dynamic>;
        final idKantor = (row['id_kantor'] as num).toInt();
        final nominal = (row['nominal'] as num).toDouble();
        final jenis = row['jenis_pinjaman'] as Map<String, dynamic>?;
        final namaJenis = (jenis?['nama_jenis'] as String?) ?? 'Lainnya';

        totalByKantor[idKantor] = (totalByKantor[idKantor] ?? 0) + nominal;
        countByKantor[idKantor] = (countByKantor[idKantor] ?? 0) + 1;
        final komposisi = komposisiByKantor.putIfAbsent(idKantor, () => {});
        komposisi[namaJenis] = (komposisi[namaJenis] ?? 0) + nominal;
      }

      final kantorList =
          kantorRows.map((raw) {
              final row = raw as Map<String, dynamic>;
              final idKantor = (row['id_kantor'] as num).toInt();
              return KantorEntry(
                idKantor: idKantor,
                namaKantor: (row['nama_kantor'] as String?) ?? '-',
                alamat: (row['alamat'] as String?) ?? '-',
                wilayah: (row['wilayah'] as String?) ?? '-',
                totalPenyaluran: totalByKantor[idKantor] ?? 0,
                jumlahTransaksi: countByKantor[idKantor] ?? 0,
                komposisiJenis: komposisiByKantor[idKantor] ?? const {},
              );
            }).toList()
            ..sort((a, b) => b.totalPenyaluran.compareTo(a.totalPenyaluran));

      final wilayahSet = <String>{for (final k in kantorList) k.wilayah};
      final wilayahList = wilayahSet.toList()..sort();

      if (!mounted) return;
      setState(() {
        _allKantor = kantorList;
        _wilayahList = wilayahList;
        _isLoading = false;
      });
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Gagal memuat data kantor: ${error.message}';
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Gagal memuat data kantor: $error';
        _isLoading = false;
      });
    }
  }

  List<KantorEntry> get _filteredKantor {
    return _allKantor.where((k) {
      final matchesWilayah =
          _selectedWilayah == 'all' || k.wilayah == _selectedWilayah;
      final matchesQuery =
          _query.isEmpty ||
          k.namaKantor.toLowerCase().contains(_query) ||
          k.kodeKantor.toLowerCase().contains(_query);
      return matchesWilayah && matchesQuery;
    }).toList();
  }

  // Helper format
  String _formatNumber(double value) => value
      .toStringAsFixed(0)
      .replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (match) => '${match[1]}.',
      );

  String _formatMiliar(double value) {
    if (value >= 1000000000) {
      return 'Rp ${(value / 1000000000).toStringAsFixed(1)} Miliar';
    }
    if (value >= 1000000) {
      return 'Rp ${(value / 1000000).toStringAsFixed(0)} Juta';
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

  // Export
  Future<void> _exportXlsx() async {
    if (_allKantor.isEmpty) {
      _showMessage('Belum ada data kantor untuk diekspor', error: true);
      return;
    }
    setState(() => _isExporting = true);
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Rekap Kantor'];
      sheet.appendRow(
        [
          'Kode',
          'Nama Kantor',
          'Wilayah',
          'Alamat',
          'Total Penyaluran (Rp)',
          'Jumlah Transaksi',
        ].map(TextCellValue.new).toList(),
      );
      for (final k in _allKantor) {
        sheet.appendRow([
          TextCellValue(k.kodeKantor),
          TextCellValue(k.namaKantor),
          TextCellValue(k.wilayah),
          TextCellValue(k.alamat),
          DoubleCellValue(k.totalPenyaluran),
          IntCellValue(k.jumlahTransaksi),
        ]);
      }
      final bytes = excel.save();
      if (bytes == null) throw StateError('Gagal membuat berkas Excel');
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/rekap_kantor_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      );
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Rekapitulasi Kantor (Excel)',
        ),
      );
    } catch (error) {
      _showMessage('Export gagal: $error', error: true);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _openDetail(KantorEntry kantor) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _KantorDetailSheet(kantor: kantor, formatMiliar: _formatMiliar),
    );
  }

  // UI
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: _buildTopBar(),
    bottomNavigationBar: const AppNavBar(currentTab: AppTab.kantor),
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
                      onPressed: _isLoading ? null : _loadData,
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
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filteredKantor;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _headerSection(),
          const SizedBox(height: 12),
          _statsRow(),
          const SizedBox(height: 12),
          _searchAndFilter(),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    filtered.isEmpty
                        ? 'Tidak Ada Hasil'
                        : 'Daftar Kantor Cabang (${filtered.length} Ditampilkan)',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified, size: 14, color: AppColors.secondary),
                    SizedBox(width: 3),
                    Text(
                      'Data Terkini',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            _emptyState()
          else
            ...filtered.map(
              (k) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _branchCard(k),
              ),
            ),
          const SizedBox(height: 8),
          _exportCard(),
        ],
      ),
    );
  }

  Widget _headerSection() {
    final aktif = _allKantor.where((k) => k.punyaTransaksi).length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PORTOFOLIO JARINGAN',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Kantor Cabang',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PulsingDot(color: AppColors.secondary),
              const SizedBox(width: 6),
              Text(
                '$aktif Operasional',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statsRow() {
    final total = _allKantor.length;
    final aktif = _allKantor.where((k) => k.punyaTransaksi).length;
    final persen = total == 0 ? 0 : ((aktif / total) * 100).round();
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _statTile(
              icon: Icons.domain_verification,
              label: 'CABANG AKTIF',
              value: '$aktif',
              iconColor: AppColors.secondary,
              decorativeCircleColor: AppColors.secondary.withValues(
                alpha: 0.12,
              ),
              captionWidget: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    size: 14,
                    color: AppColors.secondary,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '$persen% Sesuai Target',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _statTile(
              icon: Icons.map,
              label: 'WILAYAH KERJA',
              value: '${_wilayahList.length}',
              iconColor: AppColors.primary,
              decorativeCircleColor: AppColors.surfaceContainerHigh
                  .withValues(alpha: 0.6),
              captionWidget: Text(
                _wilayahList.isEmpty ? '-' : _wilayahList.join(' & '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile({
    required IconData icon,
    required String label,
    required String value,
    required Color iconColor,
    required Color decorativeCircleColor,
    required Widget captionWidget,
  }) => Container(
    padding: const EdgeInsets.all(12),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 6,
          offset: const Offset(0, 1),
        ),
      ],
    ),
    child: Stack(
      children: [
        Positioned(
          right: -12,
          bottom: -12,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: decorativeCircleColor,
              shape: BoxShape.circle,
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                Icon(icon, size: 20, color: iconColor),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            captionWidget,
          ],
        ),
      ],
    ),
  );

  Widget _searchAndFilter() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Cari nama atau kode kantor...',
            hintStyle: const TextStyle(color: AppColors.outline, fontSize: 14),
            prefixIcon: const Icon(
              Icons.search,
              size: 20,
              color: AppColors.outline,
            ),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(
                      Icons.cancel,
                      size: 18,
                      color: AppColors.outline,
                    ),
                    onPressed: () => _searchController.clear(),
                  ),
            filled: true,
            fillColor: AppColors.surfaceContainerLow,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip('Semua (${_allKantor.length})', 'all'),
              for (final wilayah in _wilayahList) ...[
                const SizedBox(width: 8),
                _filterChip(
                  '$wilayah (${_allKantor.where((k) => k.wilayah == wilayah).length})',
                  wilayah,
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  Widget _filterChip(String label, String value) {
    final selected = _selectedWilayah == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedWilayah = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF89F5E7),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? AppColors.onPrimary
                    : AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() => Container(
    padding: const EdgeInsets.all(24),
    margin: const EdgeInsets.symmetric(vertical: 8),
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
            Icons.search_off,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Kantor Tidak Ditemukan',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Tidak ada kantor cabang yang cocok dengan pencarian. Coba kata kunci lain.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () {
            _searchController.clear();
            setState(() => _selectedWilayah = 'all');
          },
          child: const Text('Reset Pencarian'),
        ),
      ],
    ),
  );

  Widget _branchCard(KantorEntry kantor) => Material(
    color: AppColors.surfaceContainerLowest,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openDetail(kantor),
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
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    kantor.idKantor.toString().padLeft(2, '0'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              kantor.kodeKantor,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: kantor.punyaTransaksi
                                  ? AppColors.secondary.withValues(alpha: 0.15)
                                  : AppColors.surfaceContainer,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: kantor.punyaTransaksi
                                        ? AppColors.secondary
                                        : AppColors.outline,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  kantor.punyaTransaksi
                                      ? 'Aktif'
                                      : 'Nonaktif',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: kantor.punyaTransaksi
                                        ? AppColors.secondary
                                        : AppColors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        kantor.namaKantor,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Regional ${kantor.wilayah}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Penyaluran Pinjaman',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          _formatMiliar(kantor.totalPenyaluran),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Jumlah Transaksi',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '${kantor.jumlahTransaksi}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: const [
                Text(
                  'Lihat Detail Kantor',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: AppColors.primary),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _exportCard() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.file_download,
            size: 20,
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Rekapitulasi Portofolio',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              Text(
                'Unduh ringkasan data ${_allKantor.length} kantor',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        FilledButton(
          onPressed: _isExporting ? null : _exportXlsx,
          child: _isExporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Ekspor XLSX'),
        ),
      ],
    ),
  );
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(
        begin: 1,
        end: 0.35,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

class _KantorDetailSheet extends StatelessWidget {
  final KantorEntry kantor;
  final String Function(double) formatMiliar;

  const _KantorDetailSheet({required this.kantor, required this.formatMiliar});

  @override
  Widget build(BuildContext context) {
    final total = kantor.totalPenyaluran;
    final entries = kantor.komposisiJenis.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
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
                          color: AppColors.surfaceContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          kantor.kodeKantor,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        kantor.namaKantor,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        'Regional ${kantor.wilayah} • ${kantor.alamat}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.onSurfaceVariant,
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
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total Penyaluran',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          formatMiliar(total),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Jumlah Transaksi',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '${kantor.jumlahTransaksi}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'KOMPOSISI JENIS PINJAMAN',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Belum ada transaksi pinjaman untuk kantor ini.',
                  style: TextStyle(color: AppColors.onSurfaceVariant),
                ),
              )
            else
              ...entries.asMap().entries.map((entry) {
                final index = entry.key;
                final namaJenis = entry.value.key;
                final nominal = entry.value.value;
                final persen = total == 0 ? 0.0 : (nominal / total * 100);
                final color =
                    _kKomposisiColors[index % _kKomposisiColors.length];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            namaJenis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.onSurface,
                            ),
                          ),
                          Text(
                            '${persen.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: persen / 100,
                          minHeight: 8,
                          backgroundColor: AppColors.surfaceContainer,
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                      ),
                    ],
                  ),
                );
              }),
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
}