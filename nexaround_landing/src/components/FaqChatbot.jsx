import { useState, useRef, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { 
  X, Sparkles, RotateCcw, 
  Maximize2, Minimize2, ThumbsUp, ThumbsDown, Check, 
  Copy, ArrowRight, HelpCircle,
  MessageSquare, Send, RefreshCw
} from 'lucide-react';
import { 
  FAQ_CATEGORIES, 
  FAQ_ITEMS 
} from '../data/faqData';
import { askGemini, isGeminiConfigured } from '../services/geminiService';

export default function FaqChatbot() {
  const navigate = useNavigate();
  const [isOpen, setIsOpen] = useState(false);
  const [isWideView, setIsWideView] = useState(false);
  const [hasUnread, setHasUnread] = useState(true);
  const [selectedCategory, setSelectedCategory] = useState('all');
  const [inputPrompt, setInputPrompt] = useState('');
  const [isTyping, setIsTyping] = useState(false);
  const [copiedIndex, setCopiedIndex] = useState(null);
  const [feedback, setFeedback] = useState({});

  const geminiActive = isGeminiConfigured();

  // Initial welcome message
  const initialMessages = [
    {
      sender: 'bot',
      text: `Hello! 👋 I'm **Neva**, your 24/7 NexAround AI Travel Concierge${geminiActive ? ' (Powered by Google Gemini)' : ''}.\n\nAsk me any question or tap a popular FAQ below:`,
      time: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
      suggestions: [
        'What is NexAround?',
        'How does the AR camera scanner work?',
        'How does Odyssey build itineraries?',
        'Is NexAround free to download?',
        'Does NexAround work offline?'
      ]
    }
  ];

  const [messages, setMessages] = useState(initialMessages);
  const latestMessageRef = useRef(null);
  const messagesContainerRef = useRef(null);
  const inputRef = useRef(null);

  // Scroll to the start of the latest question & answer so user reads it from the top
  const scrollToLatestAnswer = () => {
    if (latestMessageRef.current) {
      latestMessageRef.current.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
  };

  useEffect(() => {
    if (isOpen) {
      scrollToLatestAnswer();
      setHasUnread(false);
    }
  }, [messages, isOpen, isTyping]);

  // Focus input on open
  useEffect(() => {
    if (isOpen) {
      setTimeout(() => {
        inputRef.current?.focus();
      }, 150);
    }
  }, [isOpen]);

  // Handle message sending (via tap or typing)
  const handleSendMessage = async (textToSend) => {
    const query = (textToSend || inputPrompt).trim();
    if (!query || isTyping) return;

    const userTime = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

    // Add user question to stream
    const updatedMessages = [
      ...messages,
      { sender: 'user', text: query, time: userTime }
    ];
    setMessages(updatedMessages);
    setInputPrompt('');
    setIsTyping(true);

    try {
      // Call Google Gemini AI Service
      const botResponse = await askGemini(query, updatedMessages);
      const botTime = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

      setMessages((prev) => [
        ...prev,
        {
          sender: 'bot',
          text: botResponse.text,
          time: botTime,
          actionLinks: botResponse.actionLinks,
          suggestions: botResponse.suggestions,
          isGemini: botResponse.isGeminiPowered
        }
      ]);
    } catch (error) {
      console.error('Error getting response:', error);
    } finally {
      setIsTyping(false);
    }
  };

  const handleKeyDown = (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSendMessage();
    }
  };

  const handleResetChat = () => {
    setMessages(initialMessages);
    setFeedback({});
    setSelectedCategory('all');
    if (messagesContainerRef.current) {
      messagesContainerRef.current.scrollTo({ top: 0, behavior: 'smooth' });
    }
  };

  const handleCopy = (text, index) => {
    navigator.clipboard.writeText(text);
    setCopiedIndex(index);
    setTimeout(() => setCopiedIndex(null), 2000);
  };

  const handleActionClick = (url) => {
    if (url.startsWith('/')) {
      if (url.includes('#')) {
        const [path, hash] = url.split('#');
        navigate(path);
        setTimeout(() => {
          const elem = document.querySelector(`#${hash}`);
          if (elem) elem.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }, 150);
      } else {
        navigate(url);
        window.scrollTo({ top: 0, behavior: 'smooth' });
      }
    } else {
      window.open(url, '_blank', 'noopener,noreferrer');
    }
  };

  // Filter FAQs for category selector
  const activeCategoryFaqs = selectedCategory === 'all' 
    ? FAQ_ITEMS 
    : FAQ_ITEMS.filter(item => item.category === selectedCategory);

  // Render markdown bold and bullet points safely with JSX
  const renderFormattedText = (rawText) => {
    const lines = rawText.split('\n');
    return lines.map((line, lineIdx) => {
      if (!line.trim()) {
        return <div key={lineIdx} style={{ height: '6px' }} />;
      }

      // Parse bold segments: **bold text**
      const parts = line.split(/(\*\*.*?\*\*)/g);
      const parsedLine = parts.map((part, partIdx) => {
        if (part.startsWith('**') && part.endsWith('**')) {
          return <strong key={partIdx} style={{ color: '#ffffff', fontWeight: 600 }}>{part.slice(2, -2)}</strong>;
        }
        return part;
      });

      // Handle bullet point line
      if (line.trim().startsWith('•') || line.trim().startsWith('-')) {
        return (
          <div key={lineIdx} style={{ display: 'flex', gap: '8px', marginBottom: '3px', paddingLeft: '2px' }}>
            <span style={{ color: '#00d2d3', fontWeight: 'bold' }}>•</span>
            <span style={{ flex: 1 }}>{parsedLine}</span>
          </div>
        );
      }

      return <p key={lineIdx} style={{ margin: '0 0 5px 0', lineHeight: 1.55 }}>{parsedLine}</p>;
    });
  };

  // Index of the latest user message to attach the scroll ref to
  const latestUserMessageIdx = messages.reduce((lastIdx, msg, idx) => msg.sender === 'user' ? idx : lastIdx, -1);

  return (
    <div className="faq-chatbot-root">
      
      {/* ══════════════════════════════════════════════════════════
          1. FLOATING LAUNCHER BUTTON
          ══════════════════════════════════════════════════════════ */}
      {!isOpen && (
        <div className="faq-launcher-wrapper">
          
          {/* Animated Hint Bubble */}
          {hasUnread && (
            <div className="faq-launcher-tooltip" onClick={() => setIsOpen(true)}>
              <span className="faq-tooltip-dot" />
              <span>Ask Neva AI & Gemini FAQ</span>
              <button 
                onClick={(e) => { e.stopPropagation(); setHasUnread(false); }}
                className="faq-tooltip-close"
                aria-label="Dismiss hint"
              >
                <X size={12} />
              </button>
            </div>
          )}

          <button
            onClick={() => {
              setIsOpen(true);
              setHasUnread(false);
            }}
            className="faq-launcher-btn"
            aria-label="Open Neva AI Chatbot"
          >
            <div className="faq-launcher-avatar-wrap">
              <img 
                src="/neva_avatar.png" 
                alt="Neva AI" 
                className="faq-launcher-avatar" 
                onError={(e) => { e.currentTarget.src = '/app_icon.png'; }}
              />
              <span className="faq-status-indicator" />
            </div>
            <div className="faq-launcher-label">
              <span className="faq-launcher-title">Neva AI</span>
              <span className="faq-launcher-subtitle">Gemini Travel FAQ</span>
            </div>
            <Sparkles className="faq-launcher-sparkle" size={16} />
          </button>
        </div>
      )}

      {/* ══════════════════════════════════════════════════════════
          2. CHATBOT WINDOW (GEMINI AI + GUIDED FAQ)
          ══════════════════════════════════════════════════════════ */}
      {isOpen && (
        <div className={`faq-chat-window ${isWideView ? 'wide-view' : ''}`}>
          
          {/* Header */}
          <div className="faq-chat-header">
            <div className="faq-header-left">
              <div className="faq-header-avatar-box">
                <img 
                  src="/neva_avatar.png" 
                  alt="Neva AI" 
                  className="faq-header-avatar"
                  onError={(e) => { e.currentTarget.src = '/app_icon.png'; }}
                />
                <span className="faq-status-indicator online" />
              </div>
              <div className="faq-header-info">
                <div className="faq-header-title-row">
                  <span className="faq-header-title">Neva AI</span>
                  <span className="faq-badge-ai">Gemini Connected</span>
                </div>
                <span className="faq-header-subtitle">24/7 Smart Travel & FAQ Concierge</span>
              </div>
            </div>

            {/* Header Controls (Reset, Wide View, Close) */}
            <div className="faq-header-controls">
              
              {/* Reset Chat */}
              <button 
                onClick={handleResetChat} 
                className="faq-ctrl-btn"
                title="Reset conversation"
                aria-label="Reset Chat"
              >
                <RotateCcw size={14} />
              </button>

              {/* Wide View / Compact View Toggle */}
              <button 
                onClick={() => setIsWideView(!isWideView)} 
                className={`faq-ctrl-btn ${isWideView ? 'active-wide' : ''}`}
                title={isWideView ? 'Switch to compact view' : 'Expand to wide view'}
                aria-label="Toggle Wide View"
              >
                {isWideView ? <Minimize2 size={14} /> : <Maximize2 size={14} />}
              </button>

              {/* Close Button */}
              <button 
                onClick={() => setIsOpen(false)} 
                className="faq-ctrl-btn close-btn"
                title="Close chat"
                aria-label="Close Chat"
              >
                <X size={16} />
              </button>
            </div>
          </div>

          {/* Category Quick Filter Pills Bar */}
          <div className="faq-category-bar">
            {FAQ_CATEGORIES.map(cat => (
              <button
                key={cat.id}
                onClick={() => {
                  setSelectedCategory(cat.id);
                }}
                className={`faq-cat-pill ${selectedCategory === cat.id ? 'active' : ''}`}
              >
                <span>{cat.label}</span>
              </button>
            ))}
          </div>

          {/* Chat Message Stream */}
          <div className="faq-messages-container" ref={messagesContainerRef}>
            
            {/* Conversation Message Bubbles */}
            {messages.map((msg, idx) => {
              const isLatestQuestionBlock = (latestUserMessageIdx !== -1 && idx === latestUserMessageIdx) || (latestUserMessageIdx === -1 && idx === 0);

              return (
                <div 
                  key={idx} 
                  ref={isLatestQuestionBlock ? latestMessageRef : null}
                  className={`faq-message-row ${msg.sender}`}
                >
                  
                  {msg.sender === 'bot' && (
                    <div className="faq-msg-avatar">
                      <img src="/neva_avatar.png" alt="Neva" onError={(e) => { e.currentTarget.src = '/app_icon.png'; }} />
                    </div>
                  )}

                  <div className={`faq-msg-bubble ${msg.sender}`}>
                    <div className="faq-msg-content">
                      {renderFormattedText(msg.text)}
                    </div>

                    {/* Action Links (e.g., Download, View Feature) */}
                    {msg.actionLinks && msg.actionLinks.length > 0 && (
                      <div className="faq-action-links-wrap">
                        {msg.actionLinks.map((action, actionIdx) => (
                          <button
                            key={actionIdx}
                            onClick={() => handleActionClick(action.url)}
                            className="faq-action-link-btn"
                          >
                            <span>{action.text}</span>
                            <ArrowRight size={12} />
                          </button>
                        ))}
                      </div>
                    )}

                    {/* Bot Footer: Timestamp, Copy & Feedback */}
                    {msg.sender === 'bot' && (
                      <div className="faq-msg-footer">
                        <span className="faq-msg-time">
                          {msg.time} {msg.isGemini ? '• ✨ Gemini' : ''}
                        </span>
                        
                        <div className="faq-msg-actions">
                          <button
                            onClick={() => handleCopy(msg.text, idx)}
                            className="faq-mini-btn"
                            title="Copy answer"
                            aria-label="Copy message"
                          >
                            {copiedIndex === idx ? <Check size={12} color="#10b981" /> : <Copy size={12} />}
                          </button>

                          <button
                            onClick={() => setFeedback(prev => ({ ...prev, [idx]: prev[idx] === 'up' ? null : 'up' }))}
                            className={`faq-mini-btn ${feedback[idx] === 'up' ? 'active-up' : ''}`}
                            title="Helpful"
                            aria-label="Thumbs Up"
                          >
                            <ThumbsUp size={12} />
                          </button>

                          <button
                            onClick={() => setFeedback(prev => ({ ...prev, [idx]: prev[idx] === 'down' ? null : 'down' }))}
                            className={`faq-mini-btn ${feedback[idx] === 'down' ? 'active-down' : ''}`}
                            title="Not helpful"
                            aria-label="Thumbs Down"
                          >
                            <ThumbsDown size={12} />
                          </button>
                        </div>
                      </div>
                    )}

                    {msg.sender === 'user' && (
                      <div className="faq-user-footer">
                        <span className="faq-msg-time user">{msg.time}</span>
                      </div>
                    )}

                    {/* Suggested follow-up questions inside message bubble */}
                    {msg.suggestions && msg.suggestions.length > 0 && (
                      <div className="faq-suggestions-chips">
                        {msg.suggestions.map((sug, sIdx) => (
                          <button
                            key={sIdx}
                            onClick={() => handleSendMessage(sug)}
                            className="faq-suggestion-chip"
                          >
                            <MessageSquare size={12} color="#00d2d3" style={{ flexShrink: 0, marginTop: '2px' }} />
                            <span>{sug}</span>
                          </button>
                        ))}
                      </div>
                    )}

                  </div>
                </div>
              );
            })}

            {/* Typing Indicator */}
            {isTyping && (
              <div className="faq-message-row bot">
                <div className="faq-msg-avatar">
                  <img src="/neva_avatar.png" alt="Neva" onError={(e) => { e.currentTarget.src = '/app_icon.png'; }} />
                </div>
                <div className="faq-msg-bubble bot typing">
                  <div className="faq-typing-dots">
                    <span className="dot" />
                    <span className="dot" />
                    <span className="dot" />
                  </div>
                  <span className="faq-typing-text">Neva is generating response...</span>
                </div>
              </div>
            )}

            {/* Available FAQ Questions for the Selected Category */}
            <div className="faq-category-suggestions-box" style={{ marginTop: '8px' }}>
              <div className="faq-cat-box-header">
                <HelpCircle size={13} color="#00d2d3" />
                <span>
                  {selectedCategory === 'all' 
                    ? 'Explore Popular Questions:' 
                    : `${FAQ_CATEGORIES.find(c => c.id === selectedCategory)?.label} Questions:`}
                </span>
              </div>
              <div className="faq-cat-questions-list">
                {activeCategoryFaqs.slice(0, 6).map(item => (
                  <button
                    key={item.id}
                    onClick={() => handleSendMessage(item.question)}
                    className="faq-cat-question-btn"
                  >
                    <span className="faq-dot" />
                    <span>{item.question}</span>
                  </button>
                ))}
              </div>
            </div>

          </div>

          {/* Interactive Input Bar for Gemini AI + Reset */}
          <div className="faq-gemini-input-container">
            <div className="faq-input-wrapper">
              <input
                ref={inputRef}
                type="text"
                value={inputPrompt}
                onChange={(e) => setInputPrompt(e.target.value.slice(0, 300))}
                onKeyDown={handleKeyDown}
                placeholder="Ask Neva AI anything about travel or NexAround..."
                className="faq-text-input"
                maxLength={300}
                aria-label="Ask Neva AI a question"
              />
              <button
                onClick={() => handleSendMessage()}
                disabled={!inputPrompt.trim() || isTyping}
                className="faq-send-btn"
                aria-label="Send message to Gemini AI"
              >
                <Send size={14} />
              </button>
            </div>
            
            <div className="faq-gemini-subfooter">
              <span className="faq-footer-note">⚡ Powered by Google Gemini AI & NexAround</span>
              <button
                onClick={handleResetChat}
                className="faq-mini-reset-link"
              >
                <RefreshCw size={11} />
                <span>Reset</span>
              </button>
            </div>
          </div>

        </div>
      )}

    </div>
  );
}
