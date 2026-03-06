import { useState, useEffect, useRef } from "react";
import { useTranslation } from "react-i18next";
import { ChevronDown, Check } from "lucide-react";

interface DatePickerProps {
  value: string; // YYYY-MM-DD
  onChange: (date: string) => void;
  error?: boolean;
}

export function DatePicker({ value, onChange, error }: DatePickerProps) {
  const { t, i18n } = useTranslation();
  
  // Parse initial value or use current date components
  const [day, setDay] = useState<string>("");
  const [month, setMonth] = useState<string>("");
  const [year, setYear] = useState<string>("");
  
  const [monthOpen, setMonthOpen] = useState(false);
  const monthRef = useRef<HTMLDivElement>(null);

  // Initialize from value prop
  useEffect(() => {
    if (value) {
      const parts = value.split('-');
      if (parts.length === 3) {
        setYear(parts[0]);
        setMonth(parts[1]);
        setDay(parts[2]);
      }
    }
  }, [value]);

  // Handle outside click for month dropdown
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (monthRef.current && !monthRef.current.contains(e.target as Node)) {
        setMonthOpen(false);
      }
    };
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  // Update parent when any component changes, if valid
  useEffect(() => {
    if (day && month && year && year.length === 4) {
      const paddedDay = day.padStart(2, '0');
      const paddedMonth = month.padStart(2, '0');
      onChange(`${year}-${paddedMonth}-${paddedDay}`);
    }
  }, [day, month, year, onChange]);

  // Generate month names based on current locale
  const months = Array.from({ length: 12 }, (_, i) => {
    const d = new Date(2000, i, 1);
    return {
      value: (i + 1).toString(),
      label: d.toLocaleString(i18n.language, { month: 'long' })
    };
  });

  const getDaysInMonth = (m: number, y: number) => {
    return new Date(y, m, 0).getDate();
  };

  const handleDayChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    let newDay = e.target.value.replace(/\D/g, '');
    if (newDay.length > 2) newDay = newDay.slice(0, 2);
    
    // Validate max day based on month and year if available
    if (newDay && parseInt(newDay) > 0) {
      const m = parseInt(month) || 1;
      const y = parseInt(year) || 2000;
      const maxDays = getDaysInMonth(m, y);
      if (parseInt(newDay) > maxDays) {
        newDay = maxDays.toString();
      }
    }
    setDay(newDay);
  };

  const handleYearChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    let newYear = e.target.value.replace(/\D/g, '');
    if (newYear.length > 4) newYear = newYear.slice(0, 4);
    setYear(newYear);
    
    // Re-validate day if year changes (leap years)
    if (day && month && newYear.length === 4) {
      const m = parseInt(month);
      const y = parseInt(newYear);
      const maxDays = getDaysInMonth(m, y);
      if (parseInt(day) > maxDays) {
        setDay(maxDays.toString());
      }
    }
  };

  const selectedMonthLabel = month 
    ? months.find(m => m.value === month || m.value === parseInt(month).toString())?.label 
    : t('date.month', 'Month');

  return (
    <div className="flex gap-2 w-full">
      {/* Day */}
      <div className="flex-1">
        <input
          type="text"
          inputMode="numeric"
          placeholder={t('date.day', 'DD')}
          value={day}
          onChange={handleDayChange}
          onBlur={() => {
            if (day && parseInt(day) > 0) {
              setDay(parseInt(day).toString().padStart(2, '0'));
            } else {
              setDay("");
            }
          }}
          className={`w-full bg-gray-50 dark:bg-navy-900 border text-gray-900 dark:text-white rounded-lg p-3 outline-none focus:ring-2 transition-all placeholder:text-gray-400 dark:placeholder:text-gray-500 text-center ${
            error
              ? "border-red-400 dark:border-red-500 focus:border-red-500 focus:ring-red-500/20"
              : "border-gray-300 dark:border-navy-600 focus:border-primary-500 focus:ring-primary-500/20"
          }`}
        />
      </div>

      {/* Month Dropdown */}
      <div className="flex-[2] relative" ref={monthRef}>
        <button
          type="button"
          onClick={() => setMonthOpen(!monthOpen)}
          className={`w-full flex items-center justify-between bg-gray-50 dark:bg-navy-900 border text-left rounded-lg p-3 outline-none transition-all ${
            error
              ? "border-red-400 dark:border-red-500"
              : monthOpen
                ? "border-primary-500 ring-2 ring-primary-500/20"
                : "border-gray-300 dark:border-navy-600"
          }`}
        >
          <span className={month ? "text-gray-900 dark:text-white" : "text-gray-400 dark:text-gray-500"}>
            {selectedMonthLabel}
          </span>
          <ChevronDown className={`w-4 h-4 text-gray-400 transition-transform ${monthOpen ? "rotate-180" : ""}`} />
        </button>

        {monthOpen && (
          <div className="absolute z-50 top-full mt-1 left-0 right-0 bg-white dark:bg-navy-700 rounded-lg shadow-xl border border-gray-200 dark:border-navy-600 overflow-hidden">
            <div className="max-h-48 overflow-y-auto">
              {months.map(m => (
                <button
                  key={m.value}
                  type="button"
                  onClick={() => {
                    setMonth(m.value.padStart(2, '0'));
                    setMonthOpen(false);
                    // Re-validate day
                    if (day && year.length === 4) {
                      const maxDays = getDaysInMonth(parseInt(m.value), parseInt(year));
                      if (parseInt(day) > maxDays) {
                        setDay(maxDays.toString().padStart(2, '0'));
                      }
                    }
                  }}
                  className={`w-full text-left px-3 py-2 text-sm flex items-center justify-between transition-colors ${
                    (month === m.value || month === m.value.padStart(2, '0'))
                      ? "bg-primary-50 dark:bg-primary-500/10 text-primary-600 dark:text-primary-400"
                      : "text-gray-700 dark:text-gray-200 hover:bg-gray-50 dark:hover:bg-navy-600"
                  }`}
                >
                  <span>{m.label}</span>
                  {(month === m.value || month === m.value.padStart(2, '0')) && <Check className="w-4 h-4 text-primary-500" />}
                </button>
              ))}
            </div>
          </div>
        )}
      </div>

      {/* Year */}
      <div className="flex-[1.5]">
        <input
          type="text"
          inputMode="numeric"
          placeholder={t('date.year', 'YYYY')}
          value={year}
          onChange={handleYearChange}
          onBlur={() => {
            if (year.length > 0 && year.length < 4) {
              // Simple validation/auto-complete for year
              const y = parseInt(year);
              if (y < 100) {
                // Assume 19xx for > current year trailing digits, else 20xx
                const currentYear = new Date().getFullYear();
                const currentCentury = Math.floor(currentYear / 100) * 100;
                const assumedYear = currentCentury + y > currentYear ? (currentCentury - 100) + y : currentCentury + y;
                setYear(assumedYear.toString());
              }
            }
          }}
          className={`w-full bg-gray-50 dark:bg-navy-900 border text-gray-900 dark:text-white rounded-lg p-3 outline-none focus:ring-2 transition-all placeholder:text-gray-400 dark:placeholder:text-gray-500 text-center ${
            error
              ? "border-red-400 dark:border-red-500 focus:border-red-500 focus:ring-red-500/20"
              : "border-gray-300 dark:border-navy-600 focus:border-primary-500 focus:ring-primary-500/20"
          }`}
        />
      </div>
    </div>
  );
}
