import React from 'react';
import { motion } from 'framer-motion';
import { 
  Calculator, 
  Receipt,
  BarChart3, 
  BookOpen, 
  Box, 
  Ruler,
  Users,
  Settings,
  ArrowRight, 
  Sparkles 
} from 'lucide-react';

const quickActions = [
  {
    id: 'rates',
    title: 'Sample Rate Calc',
    subtitle: '6 Core Structural Categories',
    description: 'Instant dynamic pricing for Pipe, Angle, Channel, SQR Bar, Round Bar & Flats.',
    icon: Calculator,
    badge: 'Real-time SD',
    color: 'from-red-600 to-rose-600',
    lightBg: 'bg-red-50 text-red-600 border-red-100',
  },
  {
    id: 'quotations',
    title: 'Netrate Calculator',
    subtitle: 'Base + SD + Freight + OB',
    description: 'Multi-item pricing engine, custom freight/OB, and branded PDF quotation generator.',
    icon: Receipt,
    badge: 'Quotations',
    color: 'from-emerald-600 to-teal-600',
    lightBg: 'bg-emerald-50 text-emerald-600 border-emerald-100',
  },
  {
    id: 'reports',
    title: 'Reports Dashboard',
    subtitle: 'Today’s In/Out Summary',
    description: 'Live movement summaries, category-wise physical movement, and low stock alerts.',
    icon: BarChart3,
    badge: 'Live Analytics',
    color: 'from-blue-600 to-indigo-600',
    lightBg: 'bg-blue-50 text-blue-600 border-blue-100',
  },
  {
    id: 'inventory',
    title: 'Inventory & Stock',
    subtitle: 'Physical Stock Audits',
    description: 'Real-time yard inventory, item dimensions, unit weight metrics, and inward logs.',
    icon: Box,
    badge: 'Multi-Yard',
    color: 'from-cyan-600 to-sky-600',
    lightBg: 'bg-cyan-50 text-cyan-600 border-cyan-100',
  },
  {
    id: 'sauda',
    title: 'Sauda Bookings',
    subtitle: 'Procurement & Valuations',
    description: 'Track vendor purchase contracts, committed tonnages, and weighted average rates.',
    icon: BookOpen,
    badge: 'Purchases',
    color: 'from-amber-600 to-orange-600',
    lightBg: 'bg-amber-50 text-amber-600 border-amber-100',
  },
  {
    id: 'sizes',
    title: 'Master Size Catalog',
    subtitle: 'Dimensions & Weights',
    description: 'Configure standard size difference (SD) matrices, unit weights (kg), and tolerances.',
    icon: Ruler,
    badge: 'Catalog',
    color: 'from-purple-600 to-violet-600',
    lightBg: 'bg-purple-50 text-purple-600 border-purple-100',
  },
  {
    id: 'users',
    title: 'User Management',
    subtitle: 'Access & Permissions',
    description: 'Manage staff credentials, role-based access control, and account approvals.',
    icon: Users,
    badge: 'Security',
    color: 'from-slate-700 to-slate-900',
    lightBg: 'bg-slate-100 text-slate-700 border-slate-200',
  },
  {
    id: 'settings',
    title: 'Global Settings',
    subtitle: 'System Parameters',
    description: 'Global freight values, OB charge defaults, Supabase sync, and display options.',
    icon: Settings,
    badge: 'Config',
    color: 'from-rose-600 to-pink-600',
    lightBg: 'bg-rose-50 text-rose-600 border-rose-100',
  },
];

export default function QuickActions({ setActiveTab }) {
  return (
    <section className="mb-8">
      <div className="flex items-center justify-between mb-5">
        <div>
          <h2 className="text-xl md:text-2xl font-black text-slate-800 tracking-tight flex items-center gap-2.5">
            <span>Quick Navigation</span>
            <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[11px] font-bold bg-red-50 text-red-600 border border-red-100">
              <Sparkles size={12} /> Enterprise Suite
            </span>
          </h2>
          <p className="text-slate-400 text-xs md:text-sm font-medium mt-0.5">
            Select an enterprise tool to start live calculations, configure stock, or view analytics
          </p>
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
        {quickActions.map((action, index) => {
          const Icon = action.icon;
          return (
            <motion.div
              key={action.id}
              initial={{ opacity: 0, y: 15 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.35, delay: index * 0.05 }}
              whileHover={{ y: -4, transition: { duration: 0.2 } }}
              onClick={() => setActiveTab(action.id)}
              className="glass-card bg-white/90 hover:bg-white p-6 rounded-3xl border border-slate-200/70 hover:border-red-300 shadow-sm hover:shadow-xl hover:shadow-red-500/5 transition-all cursor-pointer flex flex-col justify-between group relative overflow-hidden"
            >
              <div>
                <div className="flex items-center justify-between mb-4">
                  <div className={`w-12 h-12 rounded-2xl bg-gradient-to-tr ${action.color} text-white flex items-center justify-center shadow-md group-hover:scale-110 transition-transform duration-300`}>
                    <Icon size={22} />
                  </div>
                  <span className={`px-2.5 py-1 rounded-full text-[10px] font-bold border ${action.lightBg}`}>
                    {action.badge}
                  </span>
                </div>

                <h3 className="text-base font-extrabold text-slate-800 tracking-tight group-hover:text-red-600 transition-colors">
                  {action.title}
                </h3>
                <p className="text-xs font-semibold text-slate-400 mb-2">
                  {action.subtitle}
                </p>
                <p className="text-xs text-slate-500 leading-relaxed line-clamp-2">
                  {action.description}
                </p>
              </div>

              <div className="pt-4 mt-4 border-t border-slate-100 flex items-center justify-between text-xs font-bold text-slate-600 group-hover:text-red-600 transition-colors">
                <span>Launch Tool</span>
                <div className="w-7 h-7 rounded-xl bg-slate-50 group-hover:bg-red-50 flex items-center justify-center transition-colors">
                  <ArrowRight size={14} className="group-hover:translate-x-0.5 transition-transform" />
                </div>
              </div>
            </motion.div>
          );
        })}
      </div>
    </section>
  );
}
