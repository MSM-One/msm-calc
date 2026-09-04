import React, { useState, useMemo, useCallback } from 'react';
import { 
  Search, 
  ArrowLeft,
  ArrowUpRight, 
  ArrowDownRight, 
  Filter, 
  Download, 
  ChevronLeft, 
  ChevronRight,
  MoreVertical,
  ArrowUpDown,
  Circle
} from 'lucide-react';
import { 
  AreaChart, 
  Area, 
  XAxis, 
  YAxis, 
  CartesianGrid, 
  Tooltip, 
  ResponsiveContainer 
} from 'recharts';

// Mock Data Generation
const generateMockData = () => {
  const items = [];
  const categories = ['Hardware', 'Sanitary', 'Electrical', 'Paint', 'Tools'];
  const dealers = ['Metaroll Steel', 'Global Traders', 'BuildWell Corp', 'Prime Logistics', 'Elite Supplies'];
  
  for (let i = 1; i <= 250; i++) {
    const stockIn = Math.floor(Math.random() * 500) + 100;
    const stockOut = Math.floor(Math.random() * stockIn);
    const closingStock = stockIn - stockOut;
    
    items.push({
      id: i,
      itemName: `Item ${i} - ${String.fromCharCode(65 + (i % 26))}${String.fromCharCode(65 + ((i+5) % 26))}${String.fromCharCode(65 + ((i+10) % 26))}`,
      category: categories[i % categories.length],
      dealer: dealers[i % dealers.length],
      in: stockIn,
      out: stockOut,
      closingStock: closingStock,
      status: closingStock < 50 ? 'Low Stock' : 'In Stock'
    });
  }
  return items;
};

const chartData = [
  { name: 'Mon', value: 400 },
  { name: 'Tue', value: 300 },
  { name: 'Wed', value: 600 },
  { name: 'Thu', value: 800 },
  { name: 'Fri', value: 500 },
  { name: 'Sat', value: 900 },
  { name: 'Sun', value: 700 },
];

const InventoryReports = ({ onBack }) => {
  const [searchTerm, setSearchTerm] = useState('');
  const [currentPage, setCurrentPage] = useState(1);
  const [sortConfig, setSortConfig] = useState({ key: 'itemName', direction: 'asc' });
  const itemsPerPage = 8;

  const allItems = useMemo(() => generateMockData(), []);

  // HIGH PERFORMANCE FILTERING LOGIC
  const filteredItems = useMemo(() => {
    const lowerCaseSearch = searchTerm.toLowerCase();
    return allItems.filter(item => 
      item.itemName.toLowerCase().includes(lowerCaseSearch) ||
      item.category.toLowerCase().includes(lowerCaseSearch) ||
      item.dealer.toLowerCase().includes(lowerCaseSearch)
    );
  }, [allItems, searchTerm]);

  // Sorting Logic
  const sortedItems = useMemo(() => {
    let sortableItems = [...filteredItems];
    if (sortConfig.key) {
      sortableItems.sort((a, b) => {
        if (a[sortConfig.key] < b[sortConfig.key]) {
          return sortConfig.direction === 'asc' ? -1 : 1;
        }
        if (a[sortConfig.key] > b[sortConfig.key]) {
          return sortConfig.direction === 'asc' ? 1 : -1;
        }
        return 0;
      });
    }
    return sortableItems;
  }, [filteredItems, sortConfig]);

  // Pagination Logic
  const paginatedItems = useMemo(() => {
    const startIndex = (currentPage - 1) * itemsPerPage;
    return sortedItems.slice(startIndex, startIndex + itemsPerPage);
  }, [sortedItems, currentPage]);

  const totalPages = Math.ceil(filteredItems.length / itemsPerPage);

  const requestSort = (key) => {
    let direction = 'asc';
    if (sortConfig.key === key && sortConfig.direction === 'asc') {
      direction = 'desc';
    }
    setSortConfig({ key, direction });
  };

  const netMovement = useMemo(() => {
    return filteredItems.reduce((acc, item) => acc + (item.in - item.out), 0);
  }, [filteredItems]);

  return (
    <div className="flex flex-col gap-8 w-full p-1 animate-in fade-in slide-in-from-bottom-6 duration-700">
      {/* Search & Filter Header */}
      <div className="flex flex-col md:flex-row gap-4 items-center justify-between">
        <div className="flex items-center gap-3 w-full md:w-auto">
          {onBack && (
            <button
              onClick={onBack}
              className="p-3 rounded-2xl bg-white/50 backdrop-blur-md border border-white/30 hover:bg-white/80 text-slate-700 hover:text-slate-950 transition-all shadow-sm flex items-center justify-center cursor-pointer group"
              title="Back to Dashboard"
              aria-label="Back to Dashboard"
            >
              <ArrowLeft size={20} className="group-hover:-translate-x-0.5 transition-transform" />
            </button>
          )}
          <div className="relative w-full md:w-96 group">
          <div className="absolute inset-y-0 left-4 flex items-center pointer-events-none">
            <Search className="w-5 h-5 text-slate-400 group-hover:text-red-500 transition-colors" />
          </div>
          <input
            type="text"
            placeholder="Search Item, Category, or Dealer..."
            className="w-full pl-12 pr-4 py-3 bg-white/40 backdrop-blur-xl border border-white/20 rounded-2xl focus:outline-none focus:ring-2 focus:ring-red-500/20 focus:border-red-500/50 transition-all placeholder:text-slate-400 font-medium text-slate-700 shadow-sm"
            value={searchTerm}
            onChange={(e) => {
              setSearchTerm(e.target.value);
              setCurrentPage(1);
            }}
          />
          </div>
        </div>
        <div className="flex gap-3 w-full md:w-auto">
          <button className="flex-1 md:flex-none flex items-center justify-center gap-2 px-4 py-3 bg-white/40 backdrop-blur-md border border-white/20 rounded-2xl hover:bg-white/60 transition-all text-slate-600 font-semibold shadow-sm">
            <Filter size={20} />
            Filters
          </button>
          <button className="flex-1 md:flex-none flex items-center justify-center gap-2 px-6 py-3 bg-[#FF0000] text-white rounded-2xl hover:bg-red-600 transition-all font-bold shadow-lg shadow-red-500/30">
            <Download size={20} />
            Export
          </button>
        </div>
      </div>

      {/* Summary Bento Cards & Chart Row */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <div className="lg:col-span-1 flex flex-col gap-6">
          {/* Bento Summary Cards */}
          <div className={`p-6 rounded-3xl backdrop-blur-2xl border border-white/20 shadow-xl transition-all hover:scale-[1.02] active:scale-[0.98] cursor-default overflow-hidden relative group
            ${netMovement >= 0 ? 'bg-emerald-50/40 shadow-emerald-500/10' : 'bg-red-50/40 shadow-red-500/10'}`}>
            <div className={`absolute top-0 right-0 w-32 h-32 blur-3xl opacity-20 -mr-16 -mt-16 transition-all group-hover:opacity-30 
              ${netMovement >= 0 ? 'bg-emerald-500' : 'bg-red-500'}`} />
            
            <div className="flex items-center justify-between mb-4">
              <span className="text-slate-500 font-bold uppercase tracking-wider text-xs">Total Net Movement</span>
              {netMovement >= 0 ? 
                <ArrowUpRight className="text-emerald-500" size={24} /> : 
                <ArrowDownRight className="text-red-500" size={24} />
              }
            </div>
            <h3 className="text-4xl font-black text-slate-800 tracking-tight">
              {netMovement > 0 ? '+' : ''}{netMovement.toLocaleString()}
              <span className="text-lg text-slate-400 ml-2 font-bold">Units</span>
            </h3>
            <p className="mt-3 text-sm font-medium text-slate-500">Based on currently filtered results</p>
          </div>

          <div className="p-6 rounded-3xl bg-white/40 backdrop-blur-2xl border border-white/20 shadow-xl shadow-slate-200/40">
            <span className="text-slate-400 font-bold uppercase tracking-wider text-xs">Stock Coverage</span>
            <div className="flex items-end gap-3 mt-2">
              <h3 className="text-4xl font-black text-slate-800 tracking-tight">94%</h3>
              <span className="text-emerald-500 font-bold mb-1 flex items-center text-sm">
                <ArrowUpRight size={16} /> 2.1%
              </span>
            </div>
            <div className="w-full h-2 bg-slate-100 rounded-full mt-4 overflow-hidden">
              <div className="h-full bg-[#FF0000] w-[94%]" />
            </div>
          </div>
        </div>

        {/* Recharts AreaChart */}
        <div className="lg:col-span-2 p-6 rounded-3xl bg-white/40 backdrop-blur-2xl border border-white/20 shadow-xl shadow-slate-200/40 min-h-[350px]">
          <div className="flex items-center justify-between mb-6">
            <div>
              <h3 className="text-xl font-black text-slate-800 tracking-tight">Inventory Flow Velocity</h3>
              <p className="text-sm text-slate-500 font-medium">Weekly transaction distribution</p>
            </div>
            <select className="bg-white/50 border border-white/20 rounded-xl px-3 py-1.5 text-sm font-bold text-slate-600 focus:outline-none">
              <option>Last 7 Days</option>
              <option>Monthly</option>
            </select>
          </div>
          <div className="h-[250px] w-full">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={chartData}>
                <defs>
                  <linearGradient id="colorValue" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#FF0000" stopOpacity={0.3}/>
                    <stop offset="95%" stopColor="#FF0000" stopOpacity={0}/>
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#E2E8F0" />
                <XAxis 
                  dataKey="name" 
                  axisLine={false} 
                  tickLine={false} 
                  tick={{ fill: '#94A3B8', fontSize: 12, fontWeight: 600 }} 
                />
                <YAxis hide />
                <Tooltip 
                  contentStyle={{ 
                    backgroundColor: 'rgba(255, 255, 255, 0.8)', 
                    backdropFilter: 'blur(8px)',
                    border: '1px solid rgba(255, 255, 255, 0.3)',
                    borderRadius: '16px',
                    boxShadow: '0 10px 15px -3px rgba(0, 0, 0, 0.1)'
                  }} 
                />
                <Area 
                  type="monotone" 
                  dataKey="value" 
                  stroke="#FF0000" 
                  strokeWidth={3}
                  fillOpacity={1} 
                  fill="url(#colorValue)" 
                />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </div>
      </div>

      {/* Modern Paginated Table */}
      <div className="p-1 rounded-3xl bg-white/40 backdrop-blur-2xl border border-white/20 shadow-xl shadow-slate-200/40 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="border-b border-white/30 text-slate-400 text-xs font-black uppercase tracking-widest">
                <th className="py-5 px-6">
                  <button 
                    onClick={() => requestSort('itemName')}
                    className="flex items-center gap-2 hover:text-red-500 transition-colors"
                  >
                    Item Details <ArrowUpDown size={14} />
                  </button>
                </th>
                <th className="py-5 px-6">Category</th>
                <th className="py-5 px-6">
                  <button 
                    onClick={() => requestSort('in')}
                    className="flex items-center gap-2 hover:text-red-500 transition-colors"
                  >
                    Stock In <ArrowUpDown size={14} />
                  </button>
                </th>
                <th className="py-5 px-6">
                   <button 
                    onClick={() => requestSort('out')}
                    className="flex items-center gap-2 hover:text-red-500 transition-colors"
                  >
                    Stock Out <ArrowUpDown size={14} />
                  </button>
                </th>
                <th className="py-5 px-6">
                   <button 
                    onClick={() => requestSort('closingStock')}
                    className="flex items-center gap-2 hover:text-red-500 transition-colors"
                  >
                    Closing <ArrowUpDown size={14} />
                  </button>
                </th>
                <th className="py-5 px-6 text-right">Status</th>
              </tr>
            </thead>
            <tbody>
              {paginatedItems.map((item) => (
                <tr key={item.id} className="group border-b border-white/20 hover:bg-white/30 transition-colors">
                  <td className="py-5 px-6">
                    <div className="flex flex-col">
                      <span className="font-bold text-slate-800 text-sm group-hover:text-[#FF0000] transition-colors">{item.itemName}</span>
                      <span className="text-xs text-slate-500 font-medium">{item.dealer}</span>
                    </div>
                  </td>
                  <td className="py-5 px-6">
                    <span className="bg-slate-100 text-slate-600 px-3 py-1 rounded-lg text-xs font-bold ring-1 ring-slate-200">
                      {item.category}
                    </span>
                  </td>
                  <td className="py-5 px-6 font-bold text-slate-700 text-sm">{item.in}</td>
                  <td className="py-5 px-6 font-bold text-slate-700 text-sm">{item.out}</td>
                  <td className="py-5 px-6 font-bold text-slate-900 text-sm">{item.closingStock}</td>
                  <td className="py-5 px-6 text-right">
                    <span className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-bold
                      ${item.status === 'In Stock' 
                        ? 'bg-emerald-50 text-emerald-600 border border-emerald-100' 
                        : 'bg-orange-50 text-orange-600 border border-orange-100'}`}>
                      <Circle size={8} fill="currentColor" />
                      {item.status}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {/* Pagination Footer */}
        <div className="flex items-center justify-between p-6 border-t border-white/20">
          <span className="text-sm font-bold text-slate-500">
            Showing <span className="text-slate-800">{((currentPage - 1) * itemsPerPage) + 1}</span> to <span className="text-slate-800">{Math.min(currentPage * itemsPerPage, filteredItems.length)}</span> of <span className="text-slate-800 font-black">{filteredItems.length}</span> items
          </span>
          <div className="flex gap-2">
            <button 
              disabled={currentPage === 1}
              onClick={() => setCurrentPage(prev => prev - 1)}
              className="p-2 rounded-xl bg-white/40 border border-white/20 text-slate-400 hover:text-red-500 disabled:opacity-30 disabled:pointer-events-none transition-all"
            >
              <ChevronLeft size={20} />
            </button>
            <div className="flex gap-1 items-center px-4 font-bold text-sm text-slate-700">
              Page {currentPage} of {totalPages}
            </div>
            <button 
              disabled={currentPage >= totalPages}
              onClick={() => setCurrentPage(prev => prev + 1)}
              className="p-2 rounded-xl bg-white/40 border border-white/20 text-slate-400 hover:text-red-500 disabled:opacity-30 disabled:pointer-events-none transition-all"
            >
              <ChevronRight size={20} />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default InventoryReports;
