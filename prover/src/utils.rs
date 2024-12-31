use env_logger::Env;
use std::{fs::OpenOptions, sync::Once};

use crate::types::{ProverType, TaskType};

static LOG_INIT: Once = Once::new();

/// Initialize log
pub fn log_init(log_file: Option<String>) {
    LOG_INIT.call_once(|| {
        let mut builder = env_logger::Builder::from_env(Env::default().default_filter_or("info"));
        if let Some(file_path) = log_file {
            let target = Box::new(
                OpenOptions::new()
                    .write(true)
                    .create(true)
                    .truncate(false)
                    .open(file_path)
                    .expect("Can't create log file"),
            );
            builder.target(env_logger::Target::Pipe(target));
        }
        builder.init();
    });
}

// pub fn get_task_types(prover_types: Vec<ProverType>) -> Vec<TaskType> {
//     prover_types.into_iter().fold(Vec::new(), |mut acc, prover_type| {
//         match prover_type {
//             ProverType::Chunk => acc.push(TaskType::Chunk),
//             ProverType::Batch => {
//                 acc.push(TaskType::Batch);
//                 acc.push(TaskType::Bundle);
//             }
//         }
//         acc
//     })
// }

pub fn get_task_types(prover_type: ProverType) -> Vec<TaskType> {
    match prover_type {
        ProverType::Chunk => vec![TaskType::Chunk],
        ProverType::Batch => vec![TaskType::Batch, TaskType::Bundle],
    }
}

pub fn get_prover_type(task_type: TaskType) -> Option<ProverType> {
        match task_type {
            TaskType::Undefined => None,
            TaskType::Chunk => Some(ProverType::Chunk),
            TaskType::Batch => Some(ProverType::Batch),
            TaskType::Bundle => Some(ProverType::Batch),
        }
}