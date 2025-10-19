import React, { useCallback, useEffect, useState } from 'react';
import { useApiCaller } from '../hooks/useApiCaller';

interface Entry {
  id: number;
  horseNumber: number;
  horseName: string;
  jockey: string;
  trainer: string;
  weight?: number;
}

interface Race {
  id: number;
  date: string;
  name: string;
  venue: string;
  entries: Entry[];
}

const RaceApp: React.FC = () => {
  const { callApi } = useApiCaller();

  const [races, setRaces] = useState<Race[]>([]);
  const [selectedRace, setSelectedRace] = useState<Race | null>(null);
  const [newRace, setNewRace] = useState<Omit<Race, 'id'>>({
    date: '',
    name: '',
    venue: '',
    entries: [],
  });

  const fetchRaces = useCallback(async () => {
    try {
      const data = await callApi<Race[]>('/api/races');
      setRaces(data);
    } catch (err) {
      console.error('Fetch races failed:', err);
    }
  }, []); 
  
  const fetchRace = async (id: number) => {
    try {
      const data = await callApi<Race>(`/api/races/${id}`);
      setSelectedRace(data);
    } catch (err) {
      console.error('Fetch race failed:', err);
    }
  };

    const toIsoWithJst = (yyyyMMdd: string) => {
    if (!yyyyMMdd) return '';
    return `${yyyyMMdd}T00:00:00+09:00`;
    };

    const createRace = async () => {
    try {
        if (!newRace.date) {
        alert('Date is required');
        return;
        }
        const payload = {
        ...newRace,
        date: toIsoWithJst(newRace.date), // ← ここがポイント
        };
        const created = await callApi<Race>(`/api/races/`, true, 'POST', JSON.stringify(payload));
        alert('Race created');
        setRaces([...races, created]);
    } catch (err) {
        console.error('Create race failed:', err);
    }
    };
  

  useEffect(() => {
    fetchRaces();
  }, [fetchRaces]);

  return (
    <div style={{ padding: 20 }}>
      <h1>Races</h1>
      <table cellPadding="8" style={{ borderCollapse: 'collapse', width: '100%' }}>
        <thead>
          <tr>
            <th>ID</th>
            <th>Name</th>
            <th>Date</th>
            <th>Venue</th>
            <th>Action</th>
          </tr>
        </thead>
        <tbody>
          {races.map((race) => (
            <tr key={race.id}>
              <td>{race.id}</td>
              <td>{race.name}</td>
              <td>{race.date?.split('T')[0]}</td>
              <td>{race.venue}</td>
              <td>
                <button onClick={() => fetchRace(race.id)}>View</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      {selectedRace && (
        <div
          style={{
            marginTop: 30,
            padding: 20,
            border: '1px solid #ccc',
            borderRadius: 8,
            backgroundColor: '#f9f9f9',
          }}
        >
          <h2>
            {selectedRace.name}（{selectedRace.date?.split('T')[0]}）
          </h2>
          <p>
            <strong>Venue:</strong> {selectedRace.venue}
          </p>

          <h3>Entries</h3>
          <table cellPadding="6" style={{ borderCollapse: 'collapse' }}>
            <thead>
              <tr>
                <th>No.</th>
                <th>Horse Name</th>
                <th>Jockey</th>
                <th>Trainer</th>
                <th>Weight</th>
              </tr>
            </thead>
            <tbody>
              {selectedRace.entries.map((entry: Entry) => (
                <tr key={entry.id}>
                  <td>{entry.horseNumber}</td>
                  <td>{entry.horseName}</td>
                  <td>{entry.jockey}</td>
                  <td>{entry.trainer}</td>
                  <td>{entry.weight ?? '-'}</td>
                </tr>
              ))}
            </tbody>
          </table>

          <button onClick={() => setSelectedRace(null)} style={{ marginTop: 20 }}>
            Close
          </button>
        </div>
      )}

      <div style={{ marginTop: 30 }}>
        <h2>Create New Race</h2>
        <input type="date" onChange={(e) => setNewRace({ ...newRace, date: e.target.value })} />
        <input
          placeholder="Race name"
          onChange={(e) => setNewRace({ ...newRace, name: e.target.value })}
        />
        <input
          placeholder="Venue"
          onChange={(e) => setNewRace({ ...newRace, venue: e.target.value })}
        />
        <button onClick={createRace}>Create</button>
      </div>
    </div>
  );
};

export default RaceApp;
