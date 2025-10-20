const puppeteer = require('puppeteer-core');
const fs = require('fs');
const path = require('path');

async function takeScreenshots() {
  let browser;

  try {
    // Try to find a local Chrome/Chromium installation
    const possiblePaths = [
      '/usr/bin/chromium-browser',
      '/usr/bin/chromium',
      '/usr/bin/google-chrome-stable',
      '/usr/bin/google-chrome',
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      '/snap/bin/chromium',
      process.env.CHROME_PATH
    ].filter(Boolean);

    let executablePath;
    for (const browserPath of possiblePaths) {
      if (fs.existsSync(browserPath)) {
        executablePath = browserPath;
        break;
      }
    }

    if (!executablePath) {
      console.error('No Chrome/Chromium browser found. Please install Chrome or Chromium.');
      console.error('Tried paths:', possiblePaths);
      process.exit(1);
    }

    console.log(`Using browser at: ${executablePath}`);

    browser = await puppeteer.launch({
      executablePath,
      headless: true,
      args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage']
    });

    const page = await browser.newPage();
    await page.setViewport({ width: 1440, height: 900 });

    const htmlPath = path.join(__dirname, 'index.html');
    const htmlUrl = `file://${htmlPath}`;

    // Take light mode screenshot
    console.log('Taking light mode screenshot...');
    await page.goto(htmlUrl, { waitUntil: 'networkidle0' });

    // Wait a bit for animations
    await page.waitForTimeout(1000);

    await page.screenshot({
      path: 'screenshot-light.png',
      fullPage: true
    });
    console.log('✓ Light mode screenshot saved to screenshot-light.png');

    // Switch to dark mode
    console.log('Taking dark mode screenshot...');
    await page.evaluate(() => {
      document.documentElement.setAttribute('data-theme', 'dark');
      localStorage.setItem('theme', 'dark');
    });

    await page.waitForTimeout(500);

    await page.screenshot({
      path: 'screenshot-dark.png',
      fullPage: true
    });
    console.log('✓ Dark mode screenshot saved to screenshot-dark.png');

    await browser.close();
    console.log('\n✓ All screenshots completed successfully!');
  } catch (error) {
    console.error('Error taking screenshots:', error);
    if (browser) await browser.close();
    process.exit(1);
  }
}

takeScreenshots();
