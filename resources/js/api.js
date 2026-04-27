export default {
  defaultHeaders: {
    "Content-Type": "application/json",
    Accept: "application/json",
    "X-CSRF-TOKEN": document.querySelector('meta[name="csrf-token"]')?.getAttribute('content'),
  },

  get(url, headers = {}) {
    return this.makeRequest("GET", url, null, headers);
  },

  patch(url, data, headers = {}) {
    return this.makeRequest("PATCH", url, data, headers);
  },

  post(url, data, headers = {}) {
    return this.makeRequest("POST", url, data, headers);
  },

  put(url, data, headers = {}) {
    return this.makeRequest("PUT", url, data, headers);
  },

  delete(url, headers = {}) {
    return this.makeRequest("DELETE", url, null, headers);
  },

  makeRequest(method, url, data = null, headers = {}) {
    const options = {
      method,
      headers: {
        ...this.defaultHeaders,
        ...headers,
      },
    };

    if (data) {
      options.body = JSON.stringify(data);
    }

    let fullUrl = url;
    if (url.startsWith('/')) {
      fullUrl = currentDomain + url;
    }

    return fetch(fullUrl, options)
      .then(async (response) => {
        if (response.headers.get("content-type")?.includes("application/json")) {
          return response.json();
        }
        return response.text();
      })
      .then((data) => {
        return data;
      });
  },
};
