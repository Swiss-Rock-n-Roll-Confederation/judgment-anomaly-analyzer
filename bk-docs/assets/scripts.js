document.addEventListener('DOMContentLoaded', function() {
  // Initialize all progress bars
  document.querySelectorAll('.progress-bar').forEach(bar => {
    const percentage = bar.dataset.percentage;
    const fill = bar.querySelector('.progress-bar-fill');
    fill.style.width = `${percentage}%`;
  });

  // Initialize charts if Chart.js is available
  if (typeof Chart !== 'undefined') {
    initializeCharts();
  }
});

function initializeCharts() {
  // Removed the chart initialization for anomaliesPerPartChart
}

// Add smooth scrolling for anchor links
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
  anchor.addEventListener('click', function (e) {
    e.preventDefault();
    document.querySelector(this.getAttribute('href')).scrollIntoView({
      behavior: 'smooth'
    });
  });
});