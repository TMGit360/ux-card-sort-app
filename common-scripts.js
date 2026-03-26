/* Legacy compression utilities retained for import/export compatibility */
const settingsFlagsKey = '?';
const settingsFlagsEnum = {
  allowCategoryEditing: 1,
  isRandomized: 2,
};
const settingsDefaults = {
  allowCategoryEditing: true,
  isRandomized: false,
};
const uncategorizedKey = '#';
const reservedKeys = [settingsFlagsKey, uncategorizedKey];
const regexRemoveBasenameFromUrl = /\/[^\/]*?$/;

function loadSettings(data) {
  const settings = Object.assign({}, settingsDefaults);
  const flags = data[settingsFlagsKey] || 0;
  for (const settingName of Object.keys(settingsFlagsEnum)) {
    settings[settingName] = Boolean(settingsFlagsEnum[settingName] & flags);
  }
  return settings;
}

function saveSettings(settings) {
  let flags = 0;
  for (const [settingName, isEnabled] of Object.entries(settings)) {
    if (isEnabled) flags |= settingsFlagsEnum[settingName];
  }
  return flags;
}

async function uint8ArrayToBase64(data) {
  const base64url = await new Promise((resolve) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.readAsDataURL(new Blob([data]));
  });
  return base64url.split(',', 2)[1];
}

async function base64ToUint8Array(base64string) {
  const response = await fetch('data:;base64,' + base64string);
  const blob = await response.blob();
  return new Uint8Array(await blob.arrayBuffer());
}

async function saveToString(data) {
  const jsonString = JSON.stringify(data);
  const compressedData = pako.deflate(new TextEncoder().encode(jsonString));
  const base64String = await uint8ArrayToBase64(compressedData);
  return base64String.replaceAll('+', '-').replaceAll('/', '_');
}

async function loadFromString(webSafeBase64String) {
  const base64String = webSafeBase64String.replaceAll('-', '+').replaceAll('_', '/');
  const compressedData = await base64ToUint8Array(base64String);
  const jsonString = new TextDecoder('utf8').decode(pako.inflate(compressedData));
  return JSON.parse(jsonString);
}

function loadFromQueryParameters() {
  const data = {};
  const settings = Object.assign({}, settingsDefaults);
  const params = new URLSearchParams(window.location.search);
  const cardTexts = splitToArray(params.get('cards') || '');
  const categories = splitToArray(params.get('categories') || '');
  if (params.get('allowCategoryEditing') !== null) {
    settings.allowCategoryEditing = Boolean(parseInt(params.get('allowCategoryEditing'), 10));
  }
  if (params.get('isRandomized') !== null) {
    settings.isRandomized = Boolean(parseInt(params.get('isRandomized'), 10));
  }
  data[uncategorizedKey] = cardTexts;
  data[settingsFlagsKey] = saveSettings(settings);
  for (const categoryName of categories) {
    data[categoryName] = [];
  }
  return data;
}

function debounce(func, wait, immediate) {
  let timeout;
  return function debouncedFunc() {
    const context = this;
    const args = arguments;
    const later = function () {
      timeout = null;
      if (!immediate) func.apply(context, args);
    };
    const callNow = immediate && !timeout;
    clearTimeout(timeout);
    timeout = setTimeout(later, wait);
    if (callNow) func.apply(context, args);
  };
}

function asTextContent(input) {
  const tempElement = document.createElement('span');
  tempElement.textContent = input;
  return tempElement.innerHTML;
}

function setContentEditablePlaintext(element) {
  element.setAttribute('contenteditable', 'PLAINTEXT-ONLY');
  const isPlaintextSupported = element.contentEditable === 'plaintext-only';
  element.addEventListener('keydown', function(event) {
    if (event.key === 'Enter') {
      element.blur();
      event.preventDefault();
    }
  });
  element.addEventListener('blur', function() {
    element.textContent = element.textContent;
  });
  if (isPlaintextSupported) return;
  element.contentEditable = true;
  const observer = new MutationObserver(plaintextOnlyMutationHandler);
  observer.observe(element, {childList: true, subtree: true});
}

function plaintextOnlyMutationHandler(mutationList) {
  for (const mutation of mutationList) {
    for (const addedNode of mutation.addedNodes) {
      if (addedNode.nodeType === Node.ELEMENT_NODE) {
        addedNode.replaceWith(addedNode.textContent);
      }
    }
  }
}

function splitToArray(text) {
  if (!text) return [];
  let resultArray;
  if (text.trim().includes('\n')) {
    resultArray = text.split('\n');
  } else {
    resultArray = text.split(',');
  }
  return resultArray.map((item) => item.trim()).filter(Boolean);
}

function generateClientId(prefix = 'id') {
  const randomPart = crypto.getRandomValues(new Uint32Array(2));
  return `${prefix}_${Date.now().toString(36)}${randomPart[0].toString(36)}${randomPart[1].toString(36)}`;
}

function shuffleArray(items) {
  const clone = [...items];
  for (let i = clone.length - 1; i > 0; i -= 1) {
    const j = Math.floor(Math.random() * (i + 1));
    [clone[i], clone[j]] = [clone[j], clone[i]];
  }
  return clone;
}

function normalizeCategoryName(name) {
  return (name || '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, ' ');
}

function parseCategoryMergeMap(text) {
  const map = {};
  const lines = (text || '').split('\n').map((line) => line.trim()).filter(Boolean);
  for (const line of lines) {
    const [left, right] = line.split('=').map((item) => (item || '').trim());
    if (left && right) {
      map[normalizeCategoryName(left)] = right;
    }
  }
  return map;
}

function categoryToMergedName(name, mergeMap) {
  return mergeMap[normalizeCategoryName(name)] || name;
}

function buildCardCategorySankeyRows(submissions, mergeMap = {}) {
  const counts = new Map();
  for (const submission of submissions) {
    const result = submission.result_json || submission.resultJson || {};
    for (const [categoryName, cards] of Object.entries(result)) {
      if (!Array.isArray(cards)) continue;
      const mergedName = categoryToMergedName(categoryName, mergeMap);
      for (const cardText of cards) {
        const key = `${cardText}|||${mergedName}`;
        counts.set(key, (counts.get(key) || 0) + 1);
      }
    }
  }
  return Array.from(counts.entries()).map(([key, count]) => {
    const [cardText, categoryName] = key.split('|||');
    return [cardText, categoryName, count];
  });
}

function buildOriginalMergedSankeyRows(submissions, mergeMap = {}) {
  const counts = new Map();
  for (const submission of submissions) {
    const result = submission.result_json || submission.resultJson || {};
    for (const categoryName of Object.keys(result)) {
      const mergedName = categoryToMergedName(categoryName, mergeMap);
      const key = `${categoryName}|||${mergedName}`;
      counts.set(key, (counts.get(key) || 0) + 1);
    }
  }
  return Array.from(counts.entries()).map(([key, count]) => {
    const [source, target] = key.split('|||');
    return [source, target, count];
  });
}

function downloadJson(filename, data) {
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}

function escapeHtml(text) {
  return asTextContent(text ?? '');
}

window.CardSortCommon = {
  settingsDefaults,
  settingsFlagsKey,
  uncategorizedKey,
  reservedKeys,
  regexRemoveBasenameFromUrl,
  loadSettings,
  saveSettings,
  saveToString,
  loadFromString,
  loadFromQueryParameters,
  splitToArray,
  generateClientId,
  shuffleArray,
  normalizeCategoryName,
  parseCategoryMergeMap,
  categoryToMergedName,
  buildCardCategorySankeyRows,
  buildOriginalMergedSankeyRows,
  downloadJson,
  escapeHtml,
  debounce,
};
