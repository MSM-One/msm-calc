const screens = [
    'screen-login',
    'screen-security',
    'screen-admin',
    'screen-feed',
    'screen-contractor',
    'screen-final'
];

let currentStep = 0;

function showScreen(index) {
    screens.forEach((id, i) => {
        const el = document.getElementById(id);
        if (i === index) {
            el.classList.add('active');
        } else {
            el.classList.remove('active');
        }
    });
}

function nextStep() {
    if (currentStep < screens.length - 1) {
        currentStep++;
        showScreen(currentStep);
    }
}

function prevStep() {
    if (currentStep > 0) {
        currentStep--;
        showScreen(currentStep);
    }
}

// Interaction Handlers
function handleLogin() {
    const loading = document.getElementById('login-loading');
    const success = document.getElementById('login-success');
    loading.style.display = 'block';
    
    setTimeout(() => {
        loading.style.display = 'none';
        success.style.display = 'block';
        setTimeout(() => {
            nextStep();
        }, 1500);
    }, 2000);
}

function handleVerify() {
    nextStep();
}

function handleRegister() {
    const loading = document.getElementById('admin-loading');
    const success = document.getElementById('admin-success');
    loading.style.display = 'block';
    
    setTimeout(() => {
        loading.style.display = 'none';
        success.style.display = 'block';
        setTimeout(() => {
            nextStep();
            initFeed();
        }, 1500);
    }, 2500);
}

function initFeed() {
    const feedList = document.getElementById('feed-list');
    feedList.innerHTML = '';
    const data = [
        { name: 'Ashok Leyland Site', time: 'Just now', pts: '+850' },
        { name: 'HP Petrol Pump #42', time: '2 mins ago', pts: '+120' },
        { name: 'Bharat Petroleum Jalna', time: '15 mins ago', pts: '+340' },
        { name: 'Reliance Smart Fuel', time: '1 hour ago', pts: '+560' },
        { name: 'IOCL Highway Express', time: '3 hours ago', pts: '+210' }
    ];

    data.forEach((item, i) => {
        setTimeout(() => {
            const div = document.createElement('div');
            div.className = 'feed-item';
            div.innerHTML = `
                <div class="feed-left">
                    <span class="feed-name">${item.name}</span>
                    <span class="feed-time">${item.time}</span>
                </div>
                <div class="feed-right">
                    <span class="feed-pts">${item.pts} Pts</span>
                </div>
            `;
            feedList.prepend(div);
        }, i * 300);
    });
}

function goToContractor() {
    nextStep();
}

function goToFinal() {
    nextStep();
}

// Keyboard shortcuts for demo
document.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowRight') nextStep();
    if (e.key === 'ArrowLeft') prevStep();
});
