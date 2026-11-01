'use client';

import { motion } from 'framer-motion';
import Link from 'next/link';
import Image from 'next/image';
import PingPongAnimation from '@/components/PingPongAnimation';
import { createClient } from '@/lib/supabase/client';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useDatabaseRefresh } from '@/lib/use-database-refresh';
import { BASE_ELO } from '@/lib/elo';

export default function HomePageClient({ playerCount, matchCount }: { playerCount: number | null; matchCount: number | null }) {
  useDatabaseRefresh('home-stats');
  const supabase = createClient();
  const router = useRouter();
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const checkAuth = async () => {
      const { data: { user } } = await supabase.auth.getUser();
      setIsLoggedIn(!!user);
      setLoading(false);
    };

    checkAuth();

    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
      setIsLoggedIn(!!session?.user);
    });

    return () => {
      subscription.unsubscribe();
    };
  }, [supabase]);
  const features = [
    {
      title: 'Competitive Ranks',
      description: 'Climb from Iron to Legend with permanent ELO, distinctive badges, and clear progress toward your next tier',
    },
    {
      title: 'Real-Time Updates',
      description: 'See challenges, active matches, rating changes, and leaderboards refresh as club results are confirmed',
    },
    {
      title: 'Live Leaderboards',
      description: 'Compare weekly and monthly ELO gains, climb the permanent ladder, and revisit previous winners',
    },
    {
      title: 'Match Tracking',
      description: 'Complete match history with detailed stats, ELO changes, and comprehensive performance analytics',
    },
  ];

  const stats = [
    { value: playerCount?.toLocaleString() ?? 'Unavailable', label: 'Registered Players' },
    { value: matchCount?.toLocaleString() ?? 'Unavailable', label: 'Confirmed Matches' },
    { value: BASE_ELO.toLocaleString(), label: 'Starting ELO' },
    { value: '24/7', label: 'Available' },
  ];

  const steps = [
    { step: '1', title: 'Challenge Players', desc: 'Send challenges to any player in the club and wait for acceptance' },
    { step: '2', title: 'Play & Report', desc: 'Either player submits the final score and the first valid report finalizes it' },
    { step: '3', title: 'Climb Rankings', desc: 'Watch your ELO update instantly and progress from Iron to Legend' },
  ];

  return (
    <div className="min-h-screen bg-gradient-to-br from-accent-white via-accent-gray-50 to-primary-purple/5">
      {/* Navigation Bar */}
      <nav className="glass-effect border-b border-accent-gray-200 sticky top-0 z-50 shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center h-20">
            <motion.div
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              className="flex items-center"
            >
                <Image
                  src="/beaver-logo.png"
                  alt="Beaver"
                  width={40}
                  height={40}
                  className="h-10 w-10 object-contain -mr-1 -mt-1"
                  priority
                />
              <span className="text-3xl font-bold gradient-text">SMASH</span>
            </motion.div>
            <motion.div
              initial={{ opacity: 0, x: 20 }}
              animate={{ opacity: 1, x: 0 }}
            >
              {!loading && (
                isLoggedIn ? (
                  <Link href="/dashboard">
                    <motion.button
                      whileHover={{ scale: 1.05 }}
                      whileTap={{ scale: 0.95 }}
                      className="px-8 py-3 gradient-purple text-white rounded-xl shadow-lg hover:shadow-purple-glow transition-all font-semibold"
                    >
                      Go to Dashboard
                    </motion.button>
                  </Link>
                ) : (
                  <Link href="/login">
                    <motion.button
                      whileHover={{ scale: 1.05 }}
                      whileTap={{ scale: 0.95 }}
                      className="px-8 py-3 gradient-purple text-white rounded-xl shadow-lg hover:shadow-purple-glow transition-all font-semibold"
                    >
                      Sign In
                    </motion.button>
                  </Link>
                )
              )}
            </motion.div>
          </div>
        </div>
      </nav>

      {/* Hero Section */}
      <section className="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pt-20 pb-32 overflow-hidden">
        {/* Background decorative elements */}
        <div className="absolute inset-0 overflow-hidden pointer-events-none">
          <motion.div
            animate={{
              x: [0, 100, 0],
              y: [0, 50, 0],
              rotate: [0, 180, 360],
            }}
            transition={{
              duration: 20,
              repeat: Infinity,
              ease: "linear",
            }}
            className="absolute top-20 left-10 w-72 h-72 bg-primary-purple/10 rounded-full blur-3xl"
          />
          <motion.div
            animate={{
              x: [0, -80, 0],
              y: [0, -60, 0],
              rotate: [360, 180, 0],
            }}
            transition={{
              duration: 25,
              repeat: Infinity,
              ease: "linear",
            }}
            className="absolute bottom-20 right-10 w-96 h-96 bg-primary-purple/5 rounded-full blur-3xl"
          />
        </div>
        
        <div className="text-center relative z-10">
          <motion.div
            initial={{ opacity: 0, y: 30 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6 }}
          >
            <motion.h1
              initial={{ opacity: 0, scale: 0.9 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ delay: 0.2, duration: 0.5 }}
              className="text-7xl md:text-8xl lg:text-9xl font-extrabold mb-8 tracking-tight"
            >
              <span className="gradient-text bg-clip-text text-transparent bg-gradient-to-r from-primary-purple via-primary-purpleLight to-primary-purple">
                Beaver Smash
              </span>
            </motion.h1>
            <motion.p
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.4 }}
              className="text-xl md:text-2xl text-accent-gray-600 mb-0 max-w-3xl mx-auto leading-relaxed font-medium"
            >
              The ultimate ELO-based ladder system. Challenge players, track your progress, and dominate the leaderboard.
            </motion.p>
          </motion.div>

          {/* Animated Table Tennis Scene - CodePen Style */}
          <motion.div
            initial={{ opacity: 0, scale: 0.8 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ delay: 0.6, duration: 0.5 }}
            className="flex justify-start items-center mb-24 -ml-12 md:-ml-24 -mt-4"
          >
            <PingPongAnimation />
          </motion.div>

            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.8 }}
              className="flex flex-col sm:flex-row gap-6 justify-center items-center"
            >
              <Link href={isLoggedIn ? "/dashboard" : "/signup"}>
              <motion.button
                whileHover={{ scale: 1.05, boxShadow: '0 0 40px rgba(124, 58, 237, 0.5)' }}
                whileTap={{ scale: 0.95 }}
                className="relative px-10 py-5 gradient-purple text-white text-xl font-bold rounded-xl shadow-2xl hover:shadow-purple-glow-lg transition-all overflow-hidden group"
              >
                <span className="relative z-10">Get Started</span>
                <motion.div
                  className="absolute inset-0 bg-gradient-to-r from-primary-purpleLight to-primary-purple opacity-0 group-hover:opacity-100 transition-opacity"
                  initial={false}
                />
              </motion.button>
            </Link>
            <motion.button
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
              onClick={() => {
                document.getElementById('features')?.scrollIntoView({ behavior: 'smooth' });
              }}
              className="px-10 py-5 bg-white border-2 border-primary-purple text-primary-purple text-xl font-bold rounded-xl shadow-lg hover:shadow-xl hover:bg-primary-purple/5 transition-all"
            >
              Learn More
            </motion.button>
          </motion.div>
        </div>
      </section>

      {/* Stats Section */}
      <section className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-20">
        <div className="grid grid-cols-2 md:grid-cols-4 gap-6 md:gap-8">
          {stats.map((stat, index) => (
            <motion.div
              key={stat.label}
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ delay: index * 0.1 }}
              whileHover={{ scale: 1.05, y: -5, boxShadow: '0 20px 40px rgba(124, 58, 237, 0.15)' }}
              className="bg-white border-2 border-accent-gray-200 rounded-2xl p-6 md:p-8 shadow-lg text-center hover:border-primary-purple/50 transition-all cursor-default"
            >
              <motion.div
                initial={{ scale: 0 }}
                whileInView={{ scale: 1 }}
                viewport={{ once: true }}
                transition={{ delay: index * 0.1 + 0.2, type: 'spring', stiffness: 200 }}
                className="text-4xl md:text-5xl font-bold gradient-text mb-3"
              >
                {stat.value}
              </motion.div>
              <div className="text-accent-gray-600 font-semibold text-base md:text-lg">{stat.label}</div>
            </motion.div>
          ))}
        </div>
      </section>

      {/* Features Section */}
      <section id="features" className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-24">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          className="text-center mb-20"
        >
          <h2 className="text-5xl md:text-6xl font-bold text-accent-black mb-6">
            Why <span className="gradient-text">Beaver Smash</span>?
          </h2>
          <p className="text-2xl text-accent-gray-600 max-w-3xl mx-auto">
            Everything you need to compete, track, and improve your table tennis game
          </p>
        </motion.div>

        <div className="grid md:grid-cols-2 gap-6 md:gap-8">
          {features.map((feature, index) => (
            <motion.div
              key={feature.title}
              initial={{ opacity: 0, y: 30 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ delay: index * 0.1 }}
              whileHover={{ scale: 1.02, y: -8, boxShadow: '0 25px 50px rgba(124, 58, 237, 0.2)' }}
              className="bg-white border-2 border-accent-gray-200 rounded-2xl p-8 md:p-10 shadow-xl hover:shadow-2xl hover:border-primary-purple transition-all group relative overflow-hidden"
            >
              <div className="absolute top-0 left-0 w-full h-1 bg-gradient-to-r from-primary-purple to-primary-purpleLight opacity-0 group-hover:opacity-100 transition-opacity" />
              <h3 className="text-2xl font-bold text-accent-black mb-4 group-hover:text-primary-purple transition-colors">{feature.title}</h3>
              <p className="text-lg text-accent-gray-600 leading-relaxed">{feature.description}</p>
            </motion.div>
          ))}
        </div>
      </section>

      {/* How It Works */}
      <section className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-24">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          className="text-center mb-20"
        >
          <h2 className="text-5xl md:text-6xl font-bold text-accent-black mb-6">
            How It <span className="gradient-text">Works</span>
          </h2>
          <p className="text-xl text-accent-gray-600 max-w-2xl mx-auto">
            Get started in three simple steps
          </p>
        </motion.div>

        <div className="grid md:grid-cols-3 gap-8 md:gap-10">
          {steps.map((item, index) => (
            <motion.div
              key={item.step}
              initial={{ opacity: 0, y: 30 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ delay: index * 0.15 }}
              whileHover={{ y: -5 }}
              className="relative"
            >
              <div className="bg-white border-2 border-primary-purple/30 rounded-2xl p-8 md:p-10 shadow-xl h-full hover:border-primary-purple hover:shadow-2xl transition-all">
                <motion.div
                  initial={{ scale: 0 }}
                  whileInView={{ scale: 1 }}
                  viewport={{ once: true }}
                  transition={{ delay: index * 0.15 + 0.2, type: 'spring', stiffness: 200 }}
                  whileHover={{ scale: 1.1, rotate: 360 }}
                  className="w-20 h-20 rounded-full gradient-purple flex items-center justify-center text-3xl font-bold text-white mb-6 shadow-lg"
                >
                  {item.step}
                </motion.div>
                <h3 className="text-2xl font-bold text-accent-black mb-4">{item.title}</h3>
                <p className="text-lg text-accent-gray-600 leading-relaxed">{item.desc}</p>
              </div>
              {index < 2 && (
                <motion.div
                  animate={{ x: [0, 5, 0] }}
                  transition={{ duration: 2, repeat: Infinity, delay: index * 0.3 }}
                  className="hidden md:block absolute top-1/2 -right-5 transform -translate-y-1/2 text-5xl text-primary-purple/50"
                >
                  →
                </motion.div>
              )}
            </motion.div>
          ))}
        </div>
      </section>

      {/* CTA Section */}
      <section className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-24">
        <motion.div
          initial={{ opacity: 0, scale: 0.9 }}
          whileInView={{ opacity: 1, scale: 1 }}
          viewport={{ once: true }}
          className="bg-gradient-to-r from-primary-purple to-primary-purpleLight rounded-3xl p-16 md:p-20 text-center shadow-2xl"
        >
          <motion.h2
            initial={{ opacity: 0, y: 20 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            className="text-5xl md:text-6xl font-bold text-white mb-8"
          >
            Ready to Compete?
          </motion.h2>
          <motion.p
            initial={{ opacity: 0, y: 20 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            transition={{ delay: 0.1 }}
            className="text-2xl text-white/90 mb-12 max-w-3xl mx-auto leading-relaxed"
          >
            Join the CCNY Table Tennis Club ladder and start your journey to the top
          </motion.p>
          <Link href={isLoggedIn ? "/dashboard" : "/signup"}>
            <motion.button
              whileHover={{ scale: 1.1, boxShadow: '0 0 50px rgba(255, 255, 255, 0.6)' }}
              whileTap={{ scale: 0.95 }}
              className="px-12 py-6 bg-white text-primary-purple text-xl font-bold rounded-xl shadow-2xl hover:shadow-white/50 transition-all"
            >
              {isLoggedIn ? "Go to Dashboard" : "Get Started Now"}
            </motion.button>
          </Link>
        </motion.div>
      </section>

      {/* Footer */}
      <footer className="border-t border-accent-gray-200 py-12 mt-24">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center text-accent-gray-600">
            <p className="font-bold text-accent-black text-xl mb-3">Beaver Smash</p>
            <p className="text-lg">CCNY Table Tennis Club • Built with passion for competition</p>
          </div>
        </div>
      </footer>
    </div>
  );
}
