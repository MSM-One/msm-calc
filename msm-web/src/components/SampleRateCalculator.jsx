import React, { useState, useMemo } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import {
  Calculator,
  Share2,
  Copy,
  Check,
  RotateCcw,
  Sparkles,
  TrendingUp,
  Percent,
  Truck,
  Layers,
  ArrowRight,
  ArrowLeft,
  ExternalLink,
  MessageCircle,
  X,
  Info
} from 'lucide-react';

// Allowed canonical categories whitelist (strictly 6 structural categories)
export const ALLOWED_CATEGORIES = [
  'MS PIPE',
  'MS ANGLE',
  'MS CHANNEL',
  'SQR BAR',
  'ROUND BAR',
  'FLATS',
];

export const isAllowedCategory = (cat) => {
  if (!cat) return false;
  const upper = cat.toUpperCase().trim();
  if (
    upper.includes('HR PIPE') ||
    upper.includes('CR PIPE') ||
    upper.includes('ISMB') ||
    upper.includes('ISMC') ||
    upper.includes('STRUCTURE') ||
    upper.includes('BEAM') ||
    upper.includes('BARBED') ||
    upper.includes('GATE') ||
    upper.includes('BINDING') ||
    upper.includes('NAIL') ||
    upper.includes('ERW')
  ) {
    return false;
  }
  return ALLOWED_CATEGORIES.some(
    (allowed) =>
      upper === allowed ||
      (allowed === 'MS PIPE' && upper.includes('PIPE')) ||
      (allowed === 'MS ANGLE' && upper.includes('ANGLE')) ||
      (allowed === 'MS CHANNEL' && upper.includes('CHANNEL')) ||
      (allowed === 'SQR BAR' &&
        (upper.includes('SQR') || upper.includes('SQUARE'))) ||
      (allowed === 'ROUND BAR' && upper.includes('ROUND')) ||
      (allowed === 'FLATS' &&
        (upper.includes('FLAT') || upper.includes('FLATS')))
  );
};

// Standard Catalog Categories and Sizes
const DEFAULT_CATALOG = {
  'MS Pipe': [
    { label: '1" 25x25 (1.6)', weight: 7, sd: 4500 },
    { label: '1.25" 41OD (2.0)', weight: 11, sd: 4500 },
    { label: '1.5" 38x38 (1.6)', weight: 11, sd: 3500 },
    { label: '1.5" 48.3OD (2.0)', weight: 13, sd: 3500 },
    { label: '2"x1" 50x25 (1.6)', weight: 11, sd: 3500 },
    { label: '2" 50x50 (1.6)', weight: 15, sd: 3500 },
    { label: '2" 60.3OD (2.0)', weight: 17, sd: 3500 },
    { label: '2.5"x1.5" 60x40 (1.6)', weight: 14, sd: 3500 },
    { label: '2.5" 60x60 (2.0)', weight: 22, sd: 4000 },
    { label: '3"x1.5" 80x40 (1.6)', weight: 17, sd: 4500 },
    { label: '3" 72x72 (2.0)', weight: 27, sd: 4500 },
    { label: '4"x2" 96x48 (1.6)', weight: 21, sd: 5500 },
  ],
  'MS Angle': [
    { label: '25x3', weight: 6.2, sd: 3000 },
    { label: '35x5', weight: 14.5, sd: 2000 },
    { label: '40x5', weight: 18, sd: 1000 },
    { label: '50x5', weight: 21.5, sd: 0 },
  ],
  'MS Channel': [
    { label: 'C 70x35 (3"x1.5")', weight: 22, sd: 2500 },
    { label: 'C 75x40 (3"x1.5")', weight: 36, sd: 1500 },
    { label: 'C 100x50 (4"x2")', weight: 56, sd: 0 },
  ],
  'SQR Bar': [
    { label: '10mm', weight: 0, sd: 1500 },
    { label: '12mm', weight: 0, sd: 0 },
  ],
  'Round Bar': [
    { label: '10mm', weight: 0, sd: 1500 },
    { label: '12mm', weight: 0, sd: 0 },
  ],
  'Flats': [
    { label: 'F 25x5', weight: 0, sd: 2000 },
    { label: 'F 32x5', weight: 0, sd: 1000 },
  ],
};

const formatIndianCurrency = (num) => {
  if (num === null || num === undefined || isNaN(num)) return '0';
  const val = Math.round(num);
  return new Intl.NumberFormat('en-IN').format(val);
};

export default function SampleRateCalculator({ onBack }) {
  // Base rates state
  const [pipeBasic, setPipeBasic] = useState('47011');
  const [angleBasic, setAngleBasic] = useState('46500');
  const [channelBasic, setChannelBasic] = useState('48000');
  const [sqrBarBasic, setSqrBarBasic] = useState('46000');
  const [roundFlatsBasic, setRoundFlatsBasic] = useState('46000');

  const [selectedCategory, setSelectedCategory] = useState('MS Pipe');
  const [isShareModalOpen, setIsShareModalOpen] = useState(false);
  const [shareFilter, setShareFilter] = useState('ALL');
  const [copied, setCopied] = useState(false);
  const [toastMessage, setToastMessage] = useState('');

  const handleBack = () => {
    if (onBack) {
      onBack();
    } else if (typeof window !== 'undefined' && window.history.length > 1) {
      window.history.back();
    }
  };

  const showToast = (msg) => {
    setToastMessage(msg);
    setTimeout(() => setToastMessage(''), 3000);
  };

  const getBasicRate = (category) => {
    const cat = category.toUpperCase();
    if (cat.includes('PIPE')) return parseFloat(pipeBasic) || 0;
    if (cat.includes('ANGLE')) return parseFloat(angleBasic) || 0;
    if (cat.includes('CHANNEL')) return parseFloat(channelBasic) || 0;
    if (cat.includes('SQR') || cat.includes('SQUARE')) return parseFloat(sqrBarBasic) || 0;
    if (cat.includes('ROUND') || cat.includes('FLAT')) return parseFloat(roundFlatsBasic) || 0;
    return parseFloat(pipeBasic) || 0;
  };

  const calculateFinalRate = (category, sd) => {
    const basic = getBasicRate(category);
    if (basic === 0) return 0;
    return Math.round(basic + sd);
  };

  const handleApplyPipeToAll = () => {
    if (!pipeBasic || parseFloat(pipeBasic) <= 0) {
      showToast('Please enter a valid Pipe rate first.');
      return;
    }
    setAngleBasic(pipeBasic);
    setChannelBasic(pipeBasic);
    setSqrBarBasic(pipeBasic);
    setRoundFlatsBasic(pipeBasic);
    showToast(`Applied ₹${formatIndianCurrency(parseFloat(pipeBasic))} to all categories!`);
  };

  // Generate WhatsApp / SMS Rate Text
  const generateRateMessage = (filterCat) => {
    const today = new Date();
    const formattedDate = `${String(today.getDate()).padStart(2, '0')}/${String(
      today.getMonth() + 1
    ).padStart(2, '0')}/${today.getFullYear()}`;

    let lines = [];
    lines.push(`Date: ${formattedDate}`);
    lines.push(`----------------------------`);

    const categories = Object.keys(DEFAULT_CATALOG).filter((cat) => {
      if (filterCat && filterCat !== 'ALL') {
        return cat.toUpperCase() === filterCat.toUpperCase();
      }
      return true;
    });

    let catIndex = 1;
    let hasAnySelected = false;

    categories.forEach((cat) => {
      const basic = getBasicRate(cat);
      if (basic > 0) {
        hasAnySelected = true;
        lines.push(`\n*${catIndex++}. ${cat.toUpperCase()}* (@₹${formatIndianCurrency(basic)})`);
        const sizes = DEFAULT_CATALOG[cat] || [];
        sizes.forEach((s) => {
          const rate = calculateFinalRate(cat, s.sd);
          const weightStr = s.weight > 0 ? ` ${s.weight}kg` : '';
          const label = `${s.label}${weightStr}`;
          lines.push(`▪ ${label} = ₹${formatIndianCurrency(rate)} /-`);
        });
      }
    });

    if (!hasAnySelected) return '';

    lines.push(`\n───────────────────────`);
    lines.push(`*Terms & Conditions*`);
    lines.push(`• Payment Advance`);
    lines.push(`• Transport (Extra)`);
    lines.push(`• Weight Tolerance - +/-5kg per MT`);

    return lines.join('\n');
  };

  const openShareModal = (initialCategory = 'ALL') => {
    setShareFilter(initialCategory);
    setIsShareModalOpen(true);
    setCopied(false);
  };

  const currentShareMessage = useMemo(() => {
    return generateRateMessage(shareFilter);
  }, [shareFilter, pipeBasic, angleBasic, channelBasic, sqrBarBasic, roundFlatsBasic]);

  const handleCopyText = async () => {
    if (!currentShareMessage) return;
    try {
      await navigator.clipboard.writeText(currentShareMessage);
      setCopied(true);
      showToast('Rate sheet copied to clipboard!');
      setTimeout(() => setCopied(false), 2500);
    } catch (e) {
      showToast('Failed to copy to clipboard');
    }
  };

  const handleWhatsAppShare = () => {
    if (!currentShareMessage) return;
    const encoded = encodeURIComponent(currentShareMessage);
    window.open(`https://api.whatsapp.com/send?text=${encoded}`, '_blank');
  };

  const handleWebShare = async () => {
    if (!currentShareMessage) return;
    if (navigator.share) {
      try {
        await navigator.share({
          title: 'MSM Steel Rates',
          text: currentShareMessage,
        });
      } catch (e) {
        // User cancelled or share failed
      }
    } else {
      handleCopyText();
    }
  };

  const activeSizes = DEFAULT_CATALOG[selectedCategory] || [];
  const currentCategoryBasic = getBasicRate(selectedCategory);

  return (
    <div className="animate-in fade-in slide-in-from-bottom-4 duration-500">
      {/* Toast Notification */}
      <AnimatePresence>
        {toastMessage && (
          <motion.div
            initial={{ opacity: 0, y: -20 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -20 }}
            className="fixed top-6 right-6 z-50 bg-slate-900 text-white px-5 py-3 rounded-2xl shadow-2xl flex items-center gap-3 border border-slate-700"
          >
            <div className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
            <span className="text-sm font-semibold">{toastMessage}</span>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Top Header Card */}
      <div className="glass-card p-6 md:p-8 mb-6 relative overflow-hidden bg-white/60 border-slate-100">
        <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-6">
          <div className="flex items-center gap-4">
            <button
              onClick={handleBack}
              className="p-3 rounded-2xl bg-white border border-slate-200/80 text-slate-700 hover:text-slate-950 hover:bg-slate-50 hover:border-slate-300 shadow-sm transition-all active:scale-95 cursor-pointer flex items-center justify-center group"
              title="Back to Dashboard"
              aria-label="Back to Dashboard"
            >
              <ArrowLeft size={20} className="group-hover:-translate-x-0.5 transition-transform text-slate-700" />
            </button>
            <div className="w-14 h-14 bg-gradient-to-tr from-red-600 to-rose-500 rounded-2xl flex items-center justify-center text-white shadow-xl shadow-red-500/20">
              <Calculator size={28} />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h1 className="text-2xl md:text-3xl font-black text-slate-800 tracking-tight m-0">
                  Sample Rate Calculator
                </h1>
                <span className="px-2.5 py-0.5 rounded-full text-[11px] font-bold bg-red-50 text-red-600 border border-red-100">
                  Live Engine
                </span>
              </div>
              <p className="text-slate-500 text-sm font-medium mt-1">
                Real-time dynamic pricing computation & multi-category quotation sharing
              </p>
            </div>
          </div>

          <div className="flex flex-wrap items-center gap-3">
            <button
              onClick={() => openShareModal('ALL')}
              className="flex items-center gap-2.5 px-6 py-3.5 bg-red-600 hover:bg-red-700 text-white font-bold text-sm rounded-2xl shadow-xl shadow-red-500/25 transition-all active:scale-95 cursor-pointer"
            >
              <Share2 size={17} />
              Share Rates Sheet
            </button>
          </div>
        </div>
      </div>

      {/* Main Content Grid: Left Config Panel + Right Rates Table */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* LEFT COLUMN: Base Rates Configuration */}
        <div className="lg:col-span-4 flex flex-col gap-6">
          <div className="glass-card p-6 bg-white/80 border-slate-100">
            <div className="flex items-center justify-between mb-5">
              <div className="flex items-center gap-2.5">
                <div className="p-2 bg-red-50 rounded-xl text-red-600">
                  <Sparkles size={18} />
                </div>
                <div>
                  <h3 className="text-base font-bold text-slate-800">Base Rates Config</h3>
                  <p className="text-xs text-slate-400 font-medium">Enter standard basic rates (₹/MT)</p>
                </div>
              </div>
            </div>

            {/* Inputs Grid */}
            <div className="space-y-3.5">
              <div>
                <label className="block text-xs font-bold text-slate-600 uppercase tracking-wider mb-1.5">
                  MS Pipe Basic (₹)
                </label>
                <div className="relative">
                  <span className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400 font-bold text-sm">₹</span>
                  <input
                    type="number"
                    value={pipeBasic}
                    onChange={(e) => setPipeBasic(e.target.value)}
                    placeholder="e.g. 47011"
                    className="w-full pl-8 pr-4 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-slate-800 font-bold text-sm focus:outline-none focus:ring-2 focus:ring-red-500/20 focus:border-red-500 transition-all"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-600 uppercase tracking-wider mb-1.5">
                  MS Angle Basic (₹)
                </label>
                <div className="relative">
                  <span className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400 font-bold text-sm">₹</span>
                  <input
                    type="number"
                    value={angleBasic}
                    onChange={(e) => setAngleBasic(e.target.value)}
                    placeholder="e.g. 46500"
                    className="w-full pl-8 pr-4 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-slate-800 font-bold text-sm focus:outline-none focus:ring-2 focus:ring-red-500/20 focus:border-red-500 transition-all"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-600 uppercase tracking-wider mb-1.5">
                  MS Channel Basic (₹)
                </label>
                <div className="relative">
                  <span className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400 font-bold text-sm">₹</span>
                  <input
                    type="number"
                    value={channelBasic}
                    onChange={(e) => setChannelBasic(e.target.value)}
                    placeholder="e.g. 48000"
                    className="w-full pl-8 pr-4 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-slate-800 font-bold text-sm focus:outline-none focus:ring-2 focus:ring-red-500/20 focus:border-red-500 transition-all"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-600 uppercase tracking-wider mb-1.5">
                  SQR Bar Basic (₹)
                </label>
                <div className="relative">
                  <span className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400 font-bold text-sm">₹</span>
                  <input
                    type="number"
                    value={sqrBarBasic}
                    onChange={(e) => setSqrBarBasic(e.target.value)}
                    placeholder="e.g. 46000"
                    className="w-full pl-8 pr-4 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-slate-800 font-bold text-sm focus:outline-none focus:ring-2 focus:ring-red-500/20 focus:border-red-500 transition-all"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-600 uppercase tracking-wider mb-1.5">
                  Round / Flats Basic (₹)
                </label>
                <div className="relative">
                  <span className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400 font-bold text-sm">₹</span>
                  <input
                    type="number"
                    value={roundFlatsBasic}
                    onChange={(e) => setRoundFlatsBasic(e.target.value)}
                    placeholder="e.g. 46000"
                    className="w-full pl-8 pr-4 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-slate-800 font-bold text-sm focus:outline-none focus:ring-2 focus:ring-red-500/20 focus:border-red-500 transition-all"
                  />
                </div>
              </div>

              {/* Broadcast Button */}
              <button
                onClick={handleApplyPipeToAll}
                className="w-full py-2.5 px-4 mt-2 bg-slate-100 hover:bg-slate-200 text-slate-700 font-bold text-xs rounded-xl transition-all flex items-center justify-center gap-2 cursor-pointer"
              >
                <Layers size={14} />
                Apply Pipe Rate to All
              </button>
            </div>

            {/* Pricing Formula Meta Strip */}
            <div className="mt-6 pt-5 border-t border-slate-100">
              <div className="p-3.5 rounded-xl bg-slate-50/80 border border-slate-100 text-[11px] text-slate-500 space-y-1">
                <div className="font-semibold text-slate-700">Pricing Formula</div>
                <div className="text-[11px] text-slate-400">
                  Computed Rate = Base Rate + Size Difference (SD)
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* RIGHT COLUMN: Interactive Pricing Table */}
        <div className="lg:col-span-8 flex flex-col gap-6">
          {/* Category Tabs */}
          <div className="flex items-center gap-2 overflow-x-auto pb-2 scrollbar-none">
            {Object.keys(DEFAULT_CATALOG).filter(isAllowedCategory).map((cat) => {
              const isSelected = selectedCategory === cat;
              const count = DEFAULT_CATALOG[cat]?.length || 0;
              const catBasic = getBasicRate(cat);

              return (
                <button
                  key={cat}
                  onClick={() => setSelectedCategory(cat)}
                  className={`
                    px-4 py-2.5 rounded-2xl font-bold text-xs whitespace-nowrap transition-all duration-300 flex items-center gap-2 cursor-pointer
                    ${
                      isSelected
                        ? 'bg-red-600 text-white shadow-lg shadow-red-500/25'
                        : 'bg-white/80 hover:bg-white text-slate-600 border border-slate-100'
                    }
                  `}
                >
                  <span>{cat.toUpperCase()}</span>
                  <span
                    className={`px-1.5 py-0.5 rounded-full text-[10px] ${
                      isSelected ? 'bg-white/20 text-white' : 'bg-slate-100 text-slate-500'
                    }`}
                  >
                    {count}
                  </span>
                  {catBasic > 0 && (
                    <span className="w-1.5 h-1.5 rounded-full bg-emerald-400" />
                  )}
                </button>
              );
            })}
          </div>

          {/* Pricing Table Card */}
          <div className="glass-card bg-white/90 border-slate-100 overflow-hidden">
            {/* Table Header Bar */}
            <div className="p-4 md:p-6 bg-slate-50/70 border-b border-slate-100 flex flex-wrap items-center justify-between gap-4">
              <div className="flex items-center gap-3">
                <h3 className="text-lg font-black text-slate-800">{selectedCategory}</h3>
                <span className="px-2 py-0.5 rounded-lg text-xs font-bold bg-slate-200/70 text-slate-700">
                  {activeSizes.length} sizes
                </span>
                <span
                  className={`px-2.5 py-0.5 rounded-lg text-xs font-bold ${
                    currentCategoryBasic > 0
                      ? 'bg-emerald-50 text-emerald-700 border border-emerald-200'
                      : 'bg-slate-100 text-slate-400'
                  }`}
                >
                  {currentCategoryBasic > 0
                    ? `Base: ₹${formatIndianCurrency(currentCategoryBasic)}/MT`
                    : 'Base Rate Not Set'}
                </span>
              </div>

              <div className="flex items-center gap-2">
                <button
                  onClick={() => openShareModal(selectedCategory)}
                  className="px-3.5 py-1.5 rounded-xl bg-red-50 hover:bg-red-100 text-red-600 text-xs font-bold flex items-center gap-1.5 border border-red-200 transition-all cursor-pointer"
                >
                  <Share2 size={13} />
                  Share {selectedCategory}
                </button>
              </div>
            </div>

            {/* Table */}
            <div className="overflow-x-auto">
              <table className="w-full text-left border-collapse">
                <thead>
                  <tr className="border-b border-slate-100 bg-slate-50/30 text-[11px] uppercase tracking-wider font-bold text-slate-400">
                    <th className="py-3.5 px-6">Size / Dimension</th>
                    <th className="py-3.5 px-4">Weight (kg)</th>
                    <th className="py-3.5 px-4">SD Value</th>
                    <th className="py-3.5 px-6 text-right">Net Computed Rate</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100 text-sm">
                  {activeSizes.map((item, idx) => {
                    const finalRate = calculateFinalRate(selectedCategory, item.sd);

                    return (
                      <tr
                        key={idx}
                        className="hover:bg-red-50/30 transition-colors group"
                      >
                        <td className="py-4 px-6 font-bold text-slate-800">
                          {item.label}
                        </td>
                        <td className="py-4 px-4 font-semibold text-slate-500">
                          {item.weight > 0 ? `${item.weight} kg` : '—'}
                        </td>
                        <td className="py-4 px-4">
                          <span
                            className={`px-2 py-0.5 rounded-md text-xs font-bold ${
                              item.sd > 0
                                ? 'bg-emerald-50 text-emerald-600'
                                : item.sd < 0
                                ? 'bg-rose-50 text-rose-600'
                                : 'bg-slate-100 text-slate-500'
                            }`}
                          >
                            {item.sd > 0 ? `+₹${item.sd}` : item.sd < 0 ? `-₹${Math.abs(item.sd)}` : '₹0'}
                          </span>
                        </td>
                        <td className="py-4 px-6 text-right">
                          <span className="font-mono font-bold text-base text-slate-900 group-hover:text-red-600 transition-colors">
                            {currentCategoryBasic > 0 ? `₹${formatIndianCurrency(finalRate)} /MT` : '—'}
                          </span>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>

      {/* SHARE RATES MODAL */}
      <AnimatePresence>
        {isShareModalOpen && (
          <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm">
            <motion.div
              initial={{ opacity: 0, scale: 0.95, y: 20 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.95, y: 20 }}
              className="bg-white rounded-3xl max-w-xl w-full p-6 shadow-2xl border border-slate-100 overflow-hidden flex flex-col max-h-[90vh]"
            >
              {/* Modal Header */}
              <div className="flex items-center justify-between pb-4 border-b border-slate-100">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 bg-red-50 text-red-600 rounded-xl flex items-center justify-center">
                    <Share2 size={20} />
                  </div>
                  <div>
                    <h3 className="text-lg font-black text-slate-800">Share Rates Preview</h3>
                    <p className="text-xs text-slate-400 font-medium">
                      Formatted quotation ready for WhatsApp & SMS
                    </p>
                  </div>
                </div>
                <button
                  onClick={() => setIsShareModalOpen(false)}
                  className="p-2 text-slate-400 hover:text-slate-600 hover:bg-slate-100 rounded-xl transition-all cursor-pointer"
                >
                  <X size={20} />
                </button>
              </div>

              {/* Category Filter Selector Inside Modal */}
              <div className="flex items-center gap-2 overflow-x-auto py-3 border-b border-slate-100 scrollbar-none">
                <button
                  onClick={() => setShareFilter('ALL')}
                  className={`px-3 py-1.5 rounded-xl text-xs font-bold whitespace-nowrap transition-all cursor-pointer ${
                    shareFilter === 'ALL'
                      ? 'bg-red-600 text-white'
                      : 'bg-slate-100 text-slate-600 hover:bg-slate-200'
                  }`}
                >
                  All Categories
                </button>
                {Object.keys(DEFAULT_CATALOG).filter(isAllowedCategory).map((cat) => (
                  <button
                    key={cat}
                    onClick={() => setShareFilter(cat)}
                    className={`px-3 py-1.5 rounded-xl text-xs font-bold whitespace-nowrap transition-all cursor-pointer ${
                      shareFilter === cat
                        ? 'bg-red-600 text-white'
                        : 'bg-slate-100 text-slate-600 hover:bg-slate-200'
                    }`}
                  >
                    {cat}
                  </button>
                ))}
              </div>

              {/* Message Preview Box */}
              <div className="flex-1 overflow-y-auto my-4 p-4 bg-slate-50 rounded-2xl border border-slate-200">
                {currentShareMessage ? (
                  <pre className="font-mono text-xs text-slate-800 leading-relaxed whitespace-pre-wrap select-all">
                    {currentShareMessage}
                  </pre>
                ) : (
                  <div className="py-12 text-center text-slate-400 text-xs">
                    No active basic rates configured for this selection.
                  </div>
                )}
              </div>

              {/* Modal Footer Actions */}
              <div className="flex flex-wrap items-center justify-end gap-3 pt-3 border-t border-slate-100">
                <button
                  onClick={handleCopyText}
                  disabled={!currentShareMessage}
                  className="flex items-center gap-2 px-4 py-2.5 bg-slate-100 hover:bg-slate-200 text-slate-700 font-bold text-xs rounded-xl transition-all cursor-pointer disabled:opacity-50"
                >
                  {copied ? <Check size={15} className="text-emerald-600" /> : <Copy size={15} />}
                  {copied ? 'Copied!' : 'Copy Text'}
                </button>

                <button
                  onClick={handleWhatsAppShare}
                  disabled={!currentShareMessage}
                  className="flex items-center gap-2 px-5 py-2.5 bg-[#25D366] hover:bg-[#20bd5a] text-white font-bold text-xs rounded-xl shadow-lg shadow-emerald-500/20 transition-all cursor-pointer disabled:opacity-50"
                >
                  <MessageCircle size={16} />
                  Share to WhatsApp
                </button>

                {navigator.share && (
                  <button
                    onClick={handleWebShare}
                    disabled={!currentShareMessage}
                    className="flex items-center gap-2 px-4 py-2.5 bg-red-600 hover:bg-red-700 text-white font-bold text-xs rounded-xl transition-all cursor-pointer disabled:opacity-50"
                  >
                    <Share2 size={15} />
                    System Share
                  </button>
                )}
              </div>
            </motion.div>
          </div>
        )}
      </AnimatePresence>
    </div>
  );
}
