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
#include <cstdlib>
#include <new>
#include <string>

#include "dcmtk/dcmdata/dctk.h"
#include "dcmtk/dcmdata/dcistrmb.h"
#include "dcmtk/dcmdata/dcdeftag.h"
#include "dcmtk/dcmdata/dcxfer.h"


static void walkDataset(DcmItem* item) {
  if (!item) return;
  DcmStack stack;
  if (item->nextObject(stack, OFTrue).good()) {
    do {
      DcmObject* obj = stack.top();
      if (!obj) break;
      (void)obj->ident();
      (void)obj->getTag();
    } while (item->nextObject(stack, OFFalse).good());
  }
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  DcmInputBufferStream in;
  in.setBuffer((void*)data, size);
  in.setEos();

  DcmFileFormat file;
  const Uint32 kMaxReadLen = 256 * 1024;

  if (file.read(in, EXS_Unknown, EGL_noChange, kMaxReadLen).bad()) return -1;
  {
    if (auto* ds = file.getDataset()) {
      (void)ds->chooseRepresentation(EXS_LittleEndianExplicit, nullptr);
      (void)ds->calcElementLength(EXS_LittleEndianExplicit, EET_ExplicitLength);

      OFString s;
      (void)ds->findAndGetOFString(DCM_PatientName, s);
      (void)ds->findAndGetOFString(DCM_StudyInstanceUID, s);
      (void)ds->findAndGetOFString(DCM_SOPClassUID, s);

      walkDataset(ds);
    }
  }
  return 0;
}
