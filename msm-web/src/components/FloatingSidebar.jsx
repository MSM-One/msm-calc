import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { 
  LayoutDashboard, 
  Calculator,
  Box, 
  BookOpen, 
  BarChart3, 
  Users, 
  Settings, 
  LogOut,
  ChevronRight,
  User
} from 'lucide-react';

const menuItems = [
  { id: 'dashboard', icon: LayoutDashboard, label: 'Dashboard' },
  { id: 'rates', icon: Calculator, label: 'Sample Rates' },
  { id: 'inventory', icon: Box, label: 'Inventory' },
  { id: 'sauda', icon: BookOpen, label: 'Sauda Book' },
  { id: 'reports', icon: BarChart3, label: 'Reports' },
  { id: 'users', icon: Users, label: 'Users' },
  { id: 'settings', icon: Settings, label: 'Settings' },
];

const FloatingSidebar = ({ activeTab, setActiveTab }) => {
  const [isExpanded, setIsExpanded] = useState(false);
  const [showLabels, setShowLabels] = useState(false);

  // Labels reveal slowly after expansion starts
  useEffect(() => {
    if (isExpanded) {
      const timer = setTimeout(() => setShowLabels(true), 150);
      return () => clearTimeout(timer);
    } else {
      setShowLabels(false);
    }
  }, [isExpanded]);

  return (
    <motion.aside
      initial={false}
      onHoverStart={() => setIsExpanded(true)}
      onHoverEnd={() => setIsExpanded(false)}
      animate={{ 
        width: isExpanded ? 256 : 80, // w-64 is 256px, w-20 is 80px
      }}
      transition={{ 
        type: 'spring', 
        stiffness: 200, 
        damping: 25,
        mass: 0.8
      }}
      className="fixed left-0 top-0 bottom-0 z-50 m-4 rounded-3xl bg-white/40 backdrop-blur-2xl border border-white/20 shadow-2xl flex flex-col items-center py-8 px-4 overflow-hidden"
    >
      {/* Brand / Logo */}
      <div className="mb-10 flex items-center justify-center w-full px-2">
        <div className="w-12 h-12 min-w-[48px] bg-red-600 rounded-2xl flex items-center justify-center text-white font-black text-2xl shadow-lg shadow-red-500/20">
          M
        </div>
        <AnimatePresence>
          {showLabels && (
            <motion.span
              initial={{ opacity: 0, x: -10 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: -10 }}
              className="ml-4 font-black text-xl text-slate-800 tracking-tight whitespace-nowrap"
            >
              MSM One
            </motion.span>
          )}
        </AnimatePresence>
      </div>

      {/* Navigation Items */}
      <div className="flex flex-col gap-3 w-full flex-1">
        {menuItems.map((item) => {
          const isActive = activeTab === item.id;
          return (
            <button
              key={item.id}
              onClick={() => setActiveTab(item.id)}
              className={`
                group relative flex items-center w-full p-3 rounded-2xl transition-all duration-300
                ${isActive ? 'bg-[#FF0000] shadow-lg shadow-red-500/40' : 'hover:bg-white/30'}
              `}
            >
              <item.icon 
                size={24}
                strokeWidth={1.5}
                className={`min-w-[24px] transition-colors duration-300 ${isActive ? 'text-white' : 'text-slate-500 group-hover:text-slate-800'}`}
              />
              
              <AnimatePresence>
                {showLabels && (
                  <motion.span
                    initial={{ opacity: 0, x: -10 }}
                    animate={{ opacity: 1, x: 0 }}
                    exit={{ opacity: 0, x: -10 }}
                    className={`ml-4 font-semibold whitespace-nowrap ${isActive ? 'text-white' : 'text-slate-600'}`}
                  >
                    {item.label}
                  </motion.span>
                )}
              </AnimatePresence>

              {isActive && !showLabels && (
                <motion.div 
                  layoutId="active-pill"
                  className="absolute right-0 w-1 h-6 bg-white rounded-l-full"
                />
              )}
            </button>
          );
        })}
      </div>

      {/* Bottom Profile Section */}
      <div className="pt-6 mt-6 border-t border-white/20 w-full">
        <div className={`
          flex items-center w-full p-3 rounded-2xl transition-all duration-300 hover:bg-white/30 cursor-pointer
        `}>
          <div className="w-10 h-10 min-w-[40px] bg-slate-100 rounded-xl flex items-center justify-center text-slate-600">
            <User size={20} strokeWidth={1.5} />
          </div>
          
          <AnimatePresence>
            {showLabels && (
              <motion.div
                initial={{ opacity: 0, x: -10 }}
                animate={{ opacity: 1, x: 0 }}
                exit={{ opacity: 0, x: -10 }}
                className="ml-3 flex flex-col overflow-hidden"
              >
                <span className="font-bold text-sm text-slate-800 whitespace-nowrap">Vivek</span>
                <span className="text-xs text-slate-500 font-medium whitespace-nowrap">Senior Admin</span>
              </motion.div>
            )}
          </AnimatePresence>
        </div>

        <button className="flex items-center w-full p-3 mt-2 rounded-2xl transition-all duration-300 hover:bg-red-50 text-slate-500 hover:text-red-600 group">
          <LogOut size={24} strokeWidth={1.5} className="min-w-[24px]" />
          <AnimatePresence>
            {showLabels && (
              <motion.span
                initial={{ opacity: 0, x: -10 }}
                animate={{ opacity: 1, x: 0 }}
                exit={{ opacity: 0, x: -10 }}
                className="ml-4 font-semibold text-sm whitespace-nowrap"
              >
                Sign Out
              </motion.span>
            )}
          </AnimatePresence>
        </button>
      </div>
    </motion.aside>
  );
};

export default FloatingSidebar;
