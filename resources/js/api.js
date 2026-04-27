export default (() => {
  const defualtHeaders = {
    'Content-Type': 'application/json',
    Accept: 'application/json',
  };

  const get = (url, headers = {}) => {
    return fetch(url, {
      method: 'GET',
      headers: {
        ...defualtHeaders,
        ...headers,
      },
    })
      .then((response) => response.json())
      .then((data) => {
        return data;
      });
  };

  return { get };
})();