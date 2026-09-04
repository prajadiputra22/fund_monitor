import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth.dart';
import '../theme/app.dart';
import '../widgets/navbar.dart';
import 'login.dart';

const List<String> _kNamaBulan = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];

/// Palet warna untuk membedakan tiap "Jenis Pinjaman" pada chart & legend.
/// Urutan mengikuti urutan jenis dengan volume tertinggi -> terendah.
const List<Color> _kJenisPalette = [
  AppColors.primary, // Jenis dengan volume #1 (Utama)
  AppColors.secondary, // #2
  Color(0xFFF2632F), // #3 (oranye, senada "on-tertiary-container" di desain)
  Color(0xFF7C93B8), // #4
  Color(0xFF9C6ADE), // #5
  Color(0xFFD9A441), // #6 dst.
];

class PendapatanEntry {
  final int idPendapatan;
  final int idKantor;
  final String namaKantor;
  final int idJenis;
  final String namaJenis;
  final int tahun;
  final int bulan;
  final double nominal;

  PendapatanEntry({
    required this.idPendapatan,
    required this.idKantor,
    required this.namaKantor,
    required this.idJenis,
    required this.namaJenis,
    required this.tahun,
    required this.bulan,
    required this.nominal,
  });

  String get namaBulan =>
      (bulan >= 1 && bulan <= 12) ? _kNamaBulan[bulan - 1] : 'Bulan $bulan';

  factory PendapatanEntry.fromMap(Map<String, dynamic> map) {
    final kantor = map['kantor'] as Map<String, dynamic>?;
    final jenis = map['jenis_pinjaman'] as Map<String, dynamic>?;
    return PendapatanEntry(
      idPendapatan: (map['id_pendapatan'] as num).toInt(),
      idKantor: (map['id_kantor'] as num).toInt(),
      namaKantor:
          (kantor?['nama_kantor'] as String?) ?? 'Kantor tidak diketahui',
      idJenis: (map['id_jenis'] as num).toInt(),
      namaJenis: (jenis?['nama_jenis'] as String?) ?? 'Jenis tidak diketahui',
      tahun: (map['tahun'] as num).toInt(),
      bulan: (map['bulan'] as num).toInt(),
      nominal: (map['nominal'] as num).toDouble(),
    );
  }
}

/// Agregat data per periode (tahun-bulan), dipakai untuk chart & info box.
class _PeriodAgg {
  final String key; // format 'YYYY-MM'
  final String label; // contoh 'Jan'
  final double total;
  final Map<String, double> byJenis;
  final String? topJenis;
  final String? topKantor;

  _PeriodAgg({
    required this.key,
    required this.label,
    required this.total,
    required this.byJenis,
    required this.topJenis,
    required this.topKantor,
  });
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _authService = AuthService();
  final _supabase = Supabase.instance.client;

  String? _selectedFileName;
  bool _isProcessing = false;
  bool _isLoading = true;
  String? _errorMessage;

  // null = tampilkan semua jenis pinjaman pada chart.
  int? _jenisFilter = 3;
  String? _selectedPeriodKey;

  List<PendapatanEntry> _loans = [];
  int _kantorCount = 0;

  Map<String, int> _kantorIdByName = {};
  Map<String, int> _jenisIdByName = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  double get _total => _loans.fold(0.0, (sum, row) => sum + row.nominal);

  // ---------------------------------------------------------------------
  // Formatting helpers
  // ---------------------------------------------------------------------

  String _formatNumber(double value) => value
      .toStringAsFixed(0)
      .replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (match) => '${match[1]}.',
      );

  /// Format ringkas gaya Indonesia, contoh: "Rp 1,42 M" / "Rp 980 Jt".
  String _formatCompact(double value) {
    if (value >= 1000000000) {
      final v = (value / 1000000000).toStringAsFixed(2).replaceAll('.', ',');
      return 'Rp $v M';
    }
    if (value >= 1000000) {
      final v = (value / 1000000).toStringAsFixed(0);
      return 'Rp $v Jt';
    }
    return 'Rp ${_formatNumber(value)}';
  }

  /// Memecah nilai besar menjadi (angka, satuan) untuk ditampilkan seperti
  /// "4,82" + "Miliar" pada kartu ringkasan utama.
  ({String value, String unit}) _splitCurrency(double value) {
    if (value >= 1000000000) {
      return (
        value: (value / 1000000000).toStringAsFixed(2).replaceAll('.', ','),
        unit: 'Miliar',
      );
    }
    if (value >= 1000000) {
      return (value: (value / 1000000).toStringAsFixed(0), unit: 'Juta');
    }
    return (value: _formatNumber(value), unit: '');
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

  // ---------------------------------------------------------------------
  // Load Database
  // ---------------------------------------------------------------------
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final results = await Future.wait([
        _supabase
            .from('pendapatan')
            .select(
              'id_pendapatan, id_kantor, id_jenis, tahun, bulan, nominal, '
              'kantor(nama_kantor, wilayah), jenis_pinjaman(nama_jenis)',
            )
            .order('tahun', ascending: true)
            .order('bulan', ascending: true),
        _supabase.from('kantor').select('id_kantor, nama_kantor'),
        _supabase.from('jenis_pinjaman').select('id_jenis, nama_jenis'),
      ]);

      final pendapatanRows = results[0] as List<dynamic>;
      final kantorRows = results[1] as List<dynamic>;
      final jenisRows = results[2] as List<dynamic>;

      final loans = pendapatanRows
          .map((row) => PendapatanEntry.fromMap(row as Map<String, dynamic>))
          .toList();

      final kantorIdByName = <String, int>{
        for (final row in kantorRows)
          (row['nama_kantor'] as String): (row['id_kantor'] as num).toInt(),
      };
      final jenisIdByName = <String, int>{
        for (final row in jenisRows)
          (row['nama_jenis'] as String): (row['id_jenis'] as num).toInt(),
      };

      if (!mounted) return;
      setState(() {
        _loans = loans;
        _kantorCount = kantorRows.length;
        _kantorIdByName = kantorIdByName;
        _jenisIdByName = jenisIdByName;
        _selectedPeriodKey = null;
        _isLoading = false;
      });
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Gagal memuat data: ${error.message}';
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Gagal memuat data: $error';
        _isLoading = false;
      });
    }
  }

  // ---------------------------------------------------------------------
  // Aggregation: periode, jenis, kantor
  // ---------------------------------------------------------------------

  List<_PeriodAgg> get _periodAggregates {
    final order = <String>[];
    final totalByPeriod = <String, double>{};
    final jenisByPeriod = <String, Map<String, double>>{};
    final kantorByPeriod = <String, Map<String, double>>{};

    for (final loan in _loans) {
      final key = '${loan.tahun}-${loan.bulan.toString().padLeft(2, '0')}';
      if (!totalByPeriod.containsKey(key)) {
        order.add(key);
        totalByPeriod[key] = 0;
        jenisByPeriod[key] = {};
        kantorByPeriod[key] = {};
      }
      totalByPeriod[key] = totalByPeriod[key]! + loan.nominal;
      final jenisMap = jenisByPeriod[key]!;
      jenisMap[loan.namaJenis] = (jenisMap[loan.namaJenis] ?? 0) + loan.nominal;
      final kantorMap = kantorByPeriod[key]!;
      kantorMap[loan.namaKantor] =
          (kantorMap[loan.namaKantor] ?? 0) + loan.nominal;
    }

    return order.map((key) {
      final bulan = int.parse(key.split('-')[1]);
      final label = (bulan >= 1 && bulan <= 12)
          ? _kNamaBulan[bulan - 1].substring(0, 3)
          : key;

      String? topOf(Map<String, double> map) {
        if (map.isEmpty) return null;
        return (map.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;
      }

      return _PeriodAgg(
        key: key,
        label: label,
        total: totalByPeriod[key]!,
        byJenis: jenisByPeriod[key]!,
        topJenis: topOf(jenisByPeriod[key]!),
        topKantor: topOf(kantorByPeriod[key]!),
      );
    }).toList();
  }

  /// Nama jenis pinjaman terurut dari volume total tertinggi -> terendah.
  List<String> get _jenisRanking {
    final totals = <String, double>{};
    for (final loan in _loans) {
      totals[loan.namaJenis] = (totals[loan.namaJenis] ?? 0) + loan.nominal;
    }
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((e) => e.key).toList();
  }

  List<MapEntry<String, double>> get _rankingKantor {
    final byKantor = <String, double>{};
    for (final loan in _loans) {
      byKantor[loan.namaKantor] =
          (byKantor[loan.namaKantor] ?? 0) + loan.nominal;
    }
    final entries = byKantor.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  int _jenisAktifUntukKantor(String namaKantor) {
    final jenisSet = <String>{};
    for (final loan in _loans) {
      if (loan.namaKantor == namaKantor) jenisSet.add(loan.namaJenis);
    }
    return jenisSet.length;
  }

  /// Pertumbuhan bulan-ke-bulan (Month over Month) dari total nominal.
  double? get _momGrowth {
    final periods = _periodAggregates;
    if (periods.length < 2) return null;
    final last = periods.last.total;
    final prev = periods[periods.length - 2].total;
    if (prev == 0) return null;
    return (last - prev) / prev * 100;
  }

  double get _rataRataBulanan {
    final periods = _periodAggregates;
    if (periods.isEmpty) return 0;
    return _total / periods.length;
  }

  double get _persenKantorAktif {
    if (_kantorCount == 0) return 0;
    final aktif = _loans.map((e) => e.namaKantor).toSet().length;
    return (aktif / _kantorCount) * 100;
  }

  // ---------------------------------------------------------------------
  // Export / Import
  // ---------------------------------------------------------------------
  Future<void> _exportExcel() async {
    if (_loans.isEmpty) {
      _showMessage('Belum ada data untuk diekspor', error: true);
      return;
    }
    setState(() => _isProcessing = true);
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Data Pinjaman'];
      sheet.appendRow(
        [
          'Tahun',
          'Bulan',
          'Kantor',
          'Jenis Pinjaman',
          'Nominal (Rp)',
        ].map(TextCellValue.new).toList(),
      );
      for (final row in _loans) {
        sheet.appendRow([
          IntCellValue(row.tahun),
          TextCellValue(row.namaBulan),
          TextCellValue(row.namaKantor),
          TextCellValue(row.namaJenis),
          DoubleCellValue(row.nominal),
        ]);
      }
      final bytes = excel.save();
      if (bytes == null) throw StateError('Gagal membuat berkas Excel');
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/fundmonitor_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      );
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Data FundMonitor (Excel)',
        ),
      );
    } catch (error) {
      _showMessage('Export Excel gagal: $error', error: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _exportPdf() async {
    if (_loans.isEmpty) {
      _showMessage('Belum ada data untuk diekspor', error: true);
      return;
    }
    setState(() => _isProcessing = true);
    try {
      final document = pw.Document();
      document.addPage(
        pw.MultiPage(
          build: (_) => [
            pw.Text(
              'Laporan FundMonitor',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Text('Total pinjaman aktif: Rp ${_formatNumber(_total)}'),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headers: ['Tahun', 'Bulan', 'Kantor', 'Jenis', 'Nominal (Rp)'],
              data: _loans
                  .map(
                    (row) => [
                      '${row.tahun}',
                      row.namaBulan,
                      row.namaKantor,
                      row.namaJenis,
                      _formatNumber(row.nominal),
                    ],
                  )
                  .toList(),
            ),
          ],
        ),
      );
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/fundmonitor_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      await file.writeAsBytes(await document.save(), flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Laporan FundMonitor (PDF)',
        ),
      );
    } catch (error) {
      _showMessage('Export PDF gagal: $error', error: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _importExcel() async {
    final selectedFile = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );
    if (selectedFile == null) return;

    final Uint8List fileBytes;
    try {
      fileBytes = await selectedFile.readAsBytes();
    } catch (_) {
      _showMessage('Gagal membaca berkas yang dipilih', error: true);
      return;
    }

    setState(() {
      _selectedFileName = selectedFile.name;
      _isProcessing = true;
    });
    try {
      final sheet = Excel.decodeBytes(fileBytes).tables.values.first;

      final rowsToInsert = <Map<String, dynamic>>[];
      final skipped = <String>[];

      // Lookup map yang case/whitespace-insensitive, dibangun sekali per import.
      final kantorIdByNormalizedName = <String, int>{
        for (final entry in _kantorIdByName.entries)
          _normalize(entry.key): entry.value,
      };
      final jenisIdByNormalizedName = <String, int>{
        for (final entry in _jenisIdByName.entries)
          _normalize(entry.key): entry.value,
      };

      for (final row in sheet.rows.skip(1)) {
        if (row.length < 5) continue;
        final values = row.map((cell) => _cellToString(cell?.value)).toList();
        if (values.take(5).any((value) => value.isEmpty)) continue;

        final tahun = int.tryParse(values[0]);
        final bulan = _parseBulan(values[1]);
        final idKantor = kantorIdByNormalizedName[_normalize(values[2])];
        final idJenis = jenisIdByNormalizedName[_normalize(values[3])];
        final nominal = double.tryParse(
          values[4].replaceAll(RegExp(r'[^0-9.]'), ''),
        );

        if (tahun == null ||
            bulan == null ||
            idKantor == null ||
            idJenis == null ||
            nominal == null) {
          skipped.add(values.join(', '));
          continue;
        }

        rowsToInsert.add({
          'id_kantor': idKantor,
          'id_jenis': idJenis,
          'tahun': tahun,
          'bulan': bulan,
          'nominal': nominal,
        });
      }

      if (rowsToInsert.isEmpty) {
        throw const FormatException(
          'Tidak ada baris valid. Pastikan kolom Kantor & Jenis Pinjaman '
          'sesuai data di master (Kantor / Jenis Pinjaman).',
        );
      }

      await _supabase.from('pendapatan').insert(rowsToInsert);
      await _loadData();

      final message = skipped.isEmpty
          ? '${rowsToInsert.length} baris berhasil diimpor'
          : '${rowsToInsert.length} baris diimpor, ${skipped.length} baris dilewati (tidak valid)';
      _showMessage(message);
    } catch (error) {
      _showMessage(
        'Import Excel gagal: format file tidak sesuai ($error)',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// Mengubah CellValue dari package `excel` menjadi String polos.
  /// `cell.value.toString()` TIDAK bisa dipakai langsung karena cell.value
  /// adalah objek CellValue (TextCellValue/IntCellValue/DoubleCellValue/...),
  /// bukan String/num mentah, sehingga toString() bisa menghasilkan
  /// representasi yang tidak sesuai isi selnya.
  String _cellToString(CellValue? value) {
    if (value == null) return '';
    return switch (value) {
      TextCellValue v => v.value.toString().trim(),
      IntCellValue v => v.value.toString(),
      DoubleCellValue v => v.value.toString(),
      BoolCellValue v => v.value.toString(),
      DateCellValue v =>
        '${v.year}-${v.month.toString().padLeft(2, '0')}-'
            '${v.day.toString().padLeft(2, '0')}',
      _ => value.toString().trim(),
    };
  }

  /// Normalisasi nama Kantor/Jenis Pinjaman agar pencocokan tidak
  /// bergantung pada huruf besar/kecil atau spasi berlebih.
  String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  int? _parseBulan(String value) {
    final asNumber = int.tryParse(value);
    if (asNumber != null && asNumber >= 1 && asNumber <= 12) return asNumber;
    final index = _kNamaBulan.indexWhere(
      (nama) => nama.toLowerCase() == value.toLowerCase(),
    );
    return index == -1 ? null : index + 1;
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: _buildAppBar(),
    bottomNavigationBar: const AppNavBar(currentTab: AppTab.dashboard),
    body: SafeArea(child: _buildBody()),
  );

  PreferredSizeWidget _buildAppBar() => AppBar(
    backgroundColor: AppColors.background.withOpacity(0.9),
    elevation: 0,
    scrolledUnderElevation: 1,
    surfaceTintColor: Colors.transparent,
    titleSpacing: 16,
    title: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: const Text(
            'P',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'FundMonitor',
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ],
    ),
    actions: [
      IconButton(
        onPressed: _isLoading ? null : _loadData,
        icon: const Icon(Icons.notifications_none_rounded),
        color: AppColors.onSurfaceVariant,
        tooltip: 'Muat ulang data',
      ),
      PopupMenuButton<String>(
        tooltip: 'Akun',
        offset: const Offset(0, 44),
        onSelected: (value) {
          if (value == 'logout') _logout();
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'logout', child: Text('Keluar')),
        ],
        child: const Padding(
          padding: EdgeInsets.only(right: 16),
          child: CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.surfaceContainer,
            child: Icon(Icons.person, color: AppColors.primary, size: 18),
          ),
        ),
      ),
    ],
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

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _overviewCards(),
            const SizedBox(height: 12),
            _chartCard(),
            const SizedBox(height: 12),
            _actionCard(),
            const SizedBox(height: 12),
            _rankingCard(),
          ],
        ),
      ),
    );
  }

  // --- Kartu Ringkasan Eksekutif -----------------------------------------

  Widget _overviewCards() {
    final growth = _momGrowth;
    final periods = _periodAggregates;
    final currency = _splitCurrency(_total);

    return Column(
      children: [
        // Card 1: Total Pinjaman (full width)
        _cardShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TOTAL PINJAMAN AKTIF',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  if (growth != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF86F2E4),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            growth >= 0
                                ? Icons.trending_up
                                : Icons.trending_down,
                            size: 13,
                            color: const Color(0xFF006F66),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(1).replaceAll('.', ',')}% MoM',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF006F66),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Text(
                    'Rp',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    currency.value,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: AppColors.primary,
                    ),
                  ),
                  if (currency.unit.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Text(
                      currency.unit,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      periods.isEmpty
                          ? 'Belum ada periode tercatat'
                          : 'Periode Berjalan (${periods.first.label} - ${periods.last.label})',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    '${_loans.length} Transaksi',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Card 2 & 3
        const SizedBox(height: 8),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _miniStatCard(
                  icon: Icons.apartment,
                  iconColor: AppColors.secondary,
                  label: 'JARINGAN KANTOR',
                  value: '$_kantorCount',
                  unit: 'Unit Aktif',
                  footerDotColor: AppColors.secondary,
                  footerText:
                      '${_persenKantorAktif.toStringAsFixed(0)}% Beroperasi',
                  footerColor: const Color(0xFF006F66),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniStatCard(
                  icon: Icons.analytics,
                  iconColor: const Color(0xFFF2632F),
                  label: 'RATA-RATA/BULAN',
                  value: _splitCurrency(_rataRataBulanan).value,
                  unit: _splitCurrency(_rataRataBulanan).unit.isEmpty
                      ? ''
                      : _splitCurrency(_rataRataBulanan).unit,
                  footerIcon: Icons.north_east,
                  footerText:
                      periods.isNotEmpty &&
                          periods.last.total >= _rataRataBulanan
                      ? 'Stabil meningkat'
                      : 'Cenderung menurun',
                  footerColor: const Color(0xFF832600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniStatCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String unit,
    String? footerText,
    Color? footerColor,
    Color? footerDotColor,
    IconData? footerIcon,
  }) => _cardShell(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                unit,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        if (footerText != null)
          Row(
            children: [
              if (footerDotColor != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: footerDotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
              ] else if (footerIcon != null) ...[
                Icon(footerIcon, size: 13, color: footerColor),
                const SizedBox(width: 3),
              ],
              Flexible(
                child: Text(
                  footerText,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: footerColor ?? AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
      ],
    ),
  );

  // --- Chart Card ----------------------------------------------------------

  Widget _chartCard() {
    final periods = _periodAggregates;
    final jenisRanking = _jenisRanking;

    final displayedJenis = _jenisFilter == null
        ? jenisRanking
        : jenisRanking.take(_jenisFilter!).toList();
    final extraJenisCount = jenisRanking.length - displayedJenis.length;

    double maxValue = 1;
    for (final period in periods) {
      for (final name in displayedJenis) {
        final v = period.byJenis[name] ?? 0;
        if (v > maxValue) maxValue = v;
      }
    }

    final kantorRanking = _rankingKantor;
    final topKantorChips = kantorRanking.take(4).toList();
    final extraKantorCount = kantorRanking.length - topKantorChips.length;

    final selected = periods.firstWhere(
      (p) => p.key == _selectedPeriodKey,
      orElse: () => periods.isNotEmpty
          ? periods.last
          : _PeriodAgg(
              key: '',
              label: '',
              total: 0,
              byJenis: const {},
              topJenis: null,
              topKantor: null,
            ),
    );
    final lastYear = periods.isNotEmpty
        ? int.parse(periods.last.key.split('-')[0])
        : DateTime.now().year;

    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _withGaps([
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Pinjaman per Bulan',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'T.A. $lastYear',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const Text(
            'Perbandingan volume per jenis pinjaman & distribusi kantor',
            style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
          ),
          // Filter jenis tertinggi
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'JUMLAH JENIS TERTINGGI:',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    value: _jenisFilter,
                    borderRadius: BorderRadius.circular(10),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 3,
                        child: Text('3 Jenis Tertinggi'),
                      ),
                      DropdownMenuItem(
                        value: 5,
                        child: Text('5 Jenis Tertinggi'),
                      ),
                      DropdownMenuItem(value: null, child: Text('Semua Jenis')),
                    ],
                    onChanged: (value) => setState(() => _jenisFilter = value),
                  ),
                ),
              ],
            ),
          ),
          // Chart area
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatCompact(maxValue),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const Text(
                      'Sentuh batang untuk rincian',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (periods.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'Belum ada data untuk ditampilkan',
                        style: TextStyle(color: AppColors.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    height: 170,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: periods.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 18),
                      itemBuilder: (context, index) {
                        final period = periods[index];
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedPeriodKey = period.key),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (
                                    var i = 0;
                                    i < displayedJenis.length;
                                    i++
                                  ) ...[
                                    if (i > 0) const SizedBox(width: 4),
                                    _bar(
                                      height:
                                          ((period.byJenis[displayedJenis[i]] ??
                                                      0) /
                                                  maxValue *
                                                  130)
                                              .clamp(2, 130)
                                              .toDouble(),
                                      color:
                                          _kJenisPalette[i %
                                              _kJenisPalette.length],
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                period.label,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: period.key == selected.key
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: AppColors.onSurface,
                                ),
                              ),
                              Text(
                                _formatCompact(period.total),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                if (periods.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 16,
                          color: AppColors.secondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            selected.key.isEmpty
                                ? '-'
                                : '${selected.label} : ${_formatCompact(selected.total)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          [
                            if (selected.topJenis != null) selected.topJenis,
                            if (selected.topKantor != null) selected.topKantor,
                          ].join(' - '),
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Legend jenis pinjaman
          if (jenisRanking.isNotEmpty) ...[
            const Text(
              'JENIS PINJAMAN:',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < displayedJenis.length; i++)
                  _legendChip(
                    color: _kJenisPalette[i % _kJenisPalette.length],
                    label: displayedJenis[i],
                  ),
                if (extraJenisCount > 0)
                  _legendChip(
                    color: AppColors.outline,
                    label: '+$extraJenisCount Jenis Lain',
                    muted: true,
                  ),
              ],
            ),
          ],
          // Legend kode kantor
          if (topKantorChips.isNotEmpty) ...[
            const Text(
              'KODE KANTOR UTAMA:',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final entry in topKantorChips) _plainChip(entry.key),
                if (extraKantorCount > 0)
                  _plainChip('+$extraKantorCount Lainnya', muted: true),
              ],
            ),
          ],
        ], 10),
      ),
    );
  }

  Widget _bar({required double height, required Color color}) => Container(
    width: 16,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
    ),
  );

  Widget _legendChip({
    required Color color,
    required String label,
    bool muted = false,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainer,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: muted ? AppColors.onSurfaceVariant : AppColors.onSurface,
          ),
        ),
      ],
    ),
  );

  Widget _plainChip(String label, {bool muted = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: muted
          ? AppColors.surfaceContainerHigh
          : AppColors.surfaceContainer,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: muted ? AppColors.onSurfaceVariant : AppColors.onSurface,
      ),
    ),
  );

  // --- Kartu Aksi & Laporan --------------------------------------------

  Widget _actionCard() => _cardShell(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _withGaps([
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Tindakan & Laporan Data',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            IconButton(
              onPressed: _isLoading ? null : _loadData,
              icon: const Icon(
                Icons.sync,
                color: AppColors.secondary,
                size: 20,
              ),
              tooltip: 'Muat ulang data',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        Row(
          children: _withGaps(
            [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _isProcessing ? null : _exportExcel,
                  icon: const Icon(Icons.table_view, size: 18),
                  label: const Text('Export Excel'),
                ),
              ),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF2632F),
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _isProcessing ? null : _exportPdf,
                  icon: const Icon(Icons.picture_as_pdf, size: 18),
                  label: const Text('Export PDF'),
                ),
              ),
            ],
            8,
            vertical: false,
          ),
        ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _withGaps([
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'SINKRONISASI BERKAS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    _selectedFileName == null
                        ? 'No file chosen'
                        : '1 berkas siap',
                    style: const TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: AppColors.surfaceContainerLowest,
                        minimumSize: const Size.fromHeight(44),
                        alignment: Alignment.centerLeft,
                        side: BorderSide(
                          color: AppColors.outline.withOpacity(0.3),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _isProcessing ? null : _importExcel,
                      icon: const Icon(
                        Icons.upload_file,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      label: Text(
                        _selectedFileName ?? 'Pilih file data (.xlsx, .xls)',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_isProcessing) const LinearProgressIndicator(),
            ], 8),
          ),
        ),
      ], 10),
    ),
  );

  // --- Ranking Kantor ------------------------------------------------------

  Widget _rankingCard() {
    final ranking = _rankingKantor.take(5).toList();
    final total = _total;

    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _withGaps([
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TOP KANTOR',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: AppColors.secondary,
                    ),
                  ),
                  Text(
                    'Ranking Penyaluran',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Lihat Semua (${_rankingKantor.length})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondary,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: AppColors.secondary,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (ranking.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Belum ada data pinjaman',
                style: TextStyle(color: AppColors.onSurfaceVariant),
              ),
            )
          else
            Column(
              children: _withGaps([
                for (var i = 0; i < ranking.length; i++)
                  _rankingRow(
                    rank: i + 1,
                    namaKantor: ranking[i].key,
                    nominal: ranking[i].value,
                    jenisCount: _jenisAktifUntukKantor(ranking[i].key),
                    persen: total == 0 ? 0 : ranking[i].value / total * 100,
                  ),
              ], 8),
            ),
        ], 12),
      ),
    );
  }

  Widget _rankingRow({
    required int rank,
    required String namaKantor,
    required double nominal,
    required int jenisCount,
    required double persen,
  }) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: rank == 1
                ? AppColors.primary
                : AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$rank',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: rank == 1 ? Colors.white : AppColors.onSurface,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                namaKantor,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              Text(
                '$jenisCount Jenis Pinjaman Dominan',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatCompact(nominal),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            Text(
              '${persen.toStringAsFixed(1).replaceAll('.', ',')}% Porsi',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.secondary,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  // --- Shell kartu umum ------------------------------------------------

  /// Menyisipkan `SizedBox` di antara setiap widget pada [children], sebagai
  /// pengganti parameter `spacing` pada Row/Column (parameter itu baru ada
  /// di Flutter versi baru, jadi cara ini lebih aman untuk semua versi).
  List<Widget> _withGaps(
    List<Widget> children,
    double gap, {
    bool vertical = true,
  }) {
    if (children.isEmpty) return children;
    final result = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        result.add(vertical ? SizedBox(height: gap) : SizedBox(width: gap));
      }
      result.add(children[i]);
    }
    return result;
  }

  Widget _cardShell({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: AppColors.primary.withOpacity(0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: child,
  );
}
