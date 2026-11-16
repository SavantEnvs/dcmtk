// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
///////////////////////////////////////////////////////////////////////////

#include <cstdint>
#include <cstddef>
#include <new>

#include "dcmtk/dcmdata/dcmetinf.h"
#include "dcmtk/dcmdata/dcistrmb.h"
#include "dcmtk/dcmdata/dcdeftag.h"
#include "dcmtk/dcmdata/dcxfer.h"


extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  DcmInputBufferStream in;
  in.setBuffer((void*)data, size);
  in.setEos();

  DcmMetaInfo mi;
  const Uint32 kMaxReadLen = 128 * 1024;
  // EXS_Unknown makes DcmMetaInfo detect the preamble and transfer syntax itself, as DcmFileFormat does;
  // with a fixed transfer syntax read() consumes nothing (the OSS-Fuzz original never parsed any input).
  if (mi.read(in, EXS_Unknown, EGL_noChange, kMaxReadLen).bad()) return -1;
  OFString s;
  (void)mi.findAndGetOFString(DCM_TransferSyntaxUID, s);
  (void)mi.findAndGetOFString(DCM_SourceApplicationEntityTitle, s);
  return 0;
}
