use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct WeatherResponse {
    pub current_weather: Option<CurrentWeather>,
    pub daily: Option<DailyForecast>,
    pub error: Option<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct CurrentWeather {
    pub temperature: f32,
    pub windspeed: f32,
    pub weathercode: i32,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct DailyForecast {
    pub time: Vec<String>,
    pub temperature_2m_max: Vec<f32>,
    pub temperature_2m_min: Vec<f32>,
    pub sunrise: Vec<String>,
    pub sunset: Vec<String>,
    pub weathercode: Vec<i32>,
}

#[derive(Deserialize, Debug)]
struct IpApiResponse {
    lat: Option<f32>,
    lon: Option<f32>,
}

#[derive(Deserialize, Debug)]
struct GeocodeResult {
    latitude: f32,
    longitude: f32,
}

#[derive(Deserialize, Debug)]
struct GeocodeResponse {
    results: Option<Vec<GeocodeResult>>,
}

// fetch coords from geoip
async fn get_geoip_coords() -> Result<(f32, f32), String> {
    let client = reqwest::Client::new();
    let res = client
        .get("http://ip-api.com/json")
        .header("user-agent", "Mozilla/5.0")
        .send()
        .await
        .map_err(|e| e.to_string())?;

    let data: IpApiResponse = res.json().await.map_err(|e| e.to_string())?;
    match (data.lat, data.lon) {
        (Some(lat), Some(lon)) => Ok((lat, lon)),
        _ => Err("failed to determine location from geoip".to_string()),
    }
}

// geocode city name to coords
async fn geocode_city(city: &str) -> Result<(f32, f32), String> {
    let url = format!(
        "https://geocoding-api.open-meteo.com/v1/search?name={}",
        percent_encoding::utf8_percent_encode(city, percent_encoding::NON_ALPHANUMERIC)
    );

    let res = reqwest::get(&url).await.map_err(|e| e.to_string())?;
    let data: GeocodeResponse = res.json().await.map_err(|e| e.to_string())?;

    if let Some(results) = data.results {
        if !results.is_empty() {
            return Ok((results[0].latitude, results[0].longitude));
        }
    }

    Err("city not found".to_string())
}

// fetch weather data from open-meteo
pub async fn fetch_weather(location: &str) -> WeatherResponse {
    let coords = if location.is_empty() {
        match get_geoip_coords().await {
            Ok(c) => c,
            Err(e) => return WeatherResponse {
                current_weather: None,
                daily: None,
                error: Some(e),
            },
        }
    } else {
        // check if location is comma-separated coords (lat,lon)
        let parts: Vec<&str> = location.split(',').collect();
        if parts.len() == 2 {
            match (parts[0].trim().parse::<f32>(), parts[1].trim().parse::<f32>()) {
                (Ok(lat), Ok(lon)) => (lat, lon),
                _ => match geocode_city(location).await {
                    Ok(c) => c,
                    Err(e) => return WeatherResponse {
                        current_weather: None,
                        daily: None,
                        error: Some(e),
                    },
                },
            }
        } else {
            match geocode_city(location).await {
                Ok(c) => c,
                Err(e) => return WeatherResponse {
                    current_weather: None,
                    daily: None,
                    error: Some(e),
                },
            }
        }
    };

    let url = format!(
        "https://api.open-meteo.com/v1/forecast?latitude={}&longitude={}&current_weather=true&daily=temperature_2m_max,temperature_2m_min,sunrise,sunset,weathercode&timezone=auto&forecast_days=7",
        coords.0, coords.1
    );

    match reqwest::get(&url).await {
        Ok(res) => match res.json::<WeatherResponse>().await {
            Ok(data) => data,
            Err(e) => WeatherResponse {
                current_weather: None,
                daily: None,
                error: Some(format!("failed to parse weather api response: {}", e)),
            },
        },
        Err(e) => WeatherResponse {
            current_weather: None,
            daily: None,
            error: Some(format!("weather api request failed: {}", e)),
        },
    }
}
